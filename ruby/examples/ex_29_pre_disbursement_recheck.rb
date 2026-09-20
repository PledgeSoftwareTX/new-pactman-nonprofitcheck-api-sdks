# frozen_string_literal: true

# EX-29 — Pre-payment or pre-disbursement recheck.
#
# An organization approved at onboarding is not an organization approved today.
# Exemptions get revoked, sanctions lists get republished, and IRS data lands on
# its own schedule — all of it after your approval and before your payout.
#
# This example rechecks immediately before the money moves, compares the fresh
# findings with the stored ones, and pauses the workflow on a material change.
# Both sets of evidence are kept: the payout is defensible only if you can show
# what you knew, and when.
#
# Run:  PACTMAN_API_KEY=... bundle exec ruby examples/ex_29_pre_disbursement_recheck.rb

require "time"
require_relative "lib/fixture_api"
require_relative "lib/print"
require_relative "lib/screening"

NCP = Pactman::NonprofitCheckPlus
include Print

EINS = FixtureApi::EINS

# Changes that stop a disbursement outright at this organization.
BLOCKING_CHANGES = %w[
  revocation_code revocation_date ofac_state bmf_status pub78_verified irs_bmf_pub78_conflict
].freeze

CLEAN_FINDINGS = {
  "bmf_status" => true,
  "exempt_status_code" => "01",
  "pub78_verified" => true,
  "revocation_code" => nil,
  "revocation_date" => nil,
  "reinstatement_date" => nil,
  "ofac_state" => "no_match",
  "irs_bmf_pub78_conflict" => false,
  "foundation_type_code" => "pc",
  "subsection_description" => "501(c)(3) Public Charity"
}.freeze

# Verification evidence stored when each payee was approved.
#
# Store the findings, not a verdict: "approved" alone cannot be re-examined.
STORED_VERIFICATIONS = {
  EINS[:public_charity] => {
    approved_at: "2026-02-11T14:05:00Z",
    request_id: "req-onboarding-8841",
    findings: CLEAN_FINDINGS.merge("organization_name" => "MEALS TODAY EXAMPLE NONPROFIT")
  },
  # Approved while in good standing. The IRS data now says otherwise.
  EINS[:revoked] => {
    approved_at: "2026-01-06T10:22:00Z",
    request_id: "req-onboarding-7310",
    findings: CLEAN_FINDINGS.merge("organization_name" => "LAPSED FILINGS EXAMPLE SOCIETY")
  }
}.freeze

PENDING_DISBURSEMENTS = [
  { payment_id: "PAY-5501", ein: EINS[:public_charity], amount: 12_400 },
  { payment_id: "PAY-5502", ein: EINS[:revoked], amount: 3_150 }
].freeze

def money(amount)
  "$#{amount.to_s.reverse.scan(/\d{1,3}/).join(",").reverse}"
end

FixtureApi.with_fixture_api do |client|
  releases = []

  PENDING_DISBURSEMENTS.each do |payment|
    heading "#{payment[:payment_id]} — #{money(payment[:amount])} to #{payment[:ein]}"

    stored = STORED_VERIFICATIONS[payment[:ein]]

    begin
      # Retries stay on: a transient failure here should be absorbed, not turned
      # into a false "changed" signal.
      result = client.nonprofits.check(payment[:ein], timeout: 10)
    rescue NCP::Error => e
      # Could not verify. That is a hold, never a release — an unreachable API is
      # not evidence that anything is fine.
      field "recheck", "failed: #{e.class.name}"
      field "decision", "HOLD — the payee could not be re-verified before payout"
      releases << payment.merge(decision: "hold", reason: "recheck_failed")
      next
    end

    if result.nonprofit.nil?
      field "recheck", "no record returned"
      field "decision", "HOLD — the payee no longer returns a record"
      releases << payment.merge(decision: "hold", reason: "no_record")
      next
    end

    current = Screening.collect_findings(result.nonprofit)
    changes = Screening.diff_findings(stored&.fetch(:findings), current)
    blocking = changes.select { |change| BLOCKING_CHANGES.include?(change.field) }
    issues = Screening.concerns(current, stale_after_days: 120)

    field "approved at", stored&.fetch(:approved_at)
    field "rechecked at", Time.now.utc.iso8601
    field "fields changed since approval", changes.size

    changes.each do |change|
      marker = BLOCKING_CHANGES.include?(change.field) ? "   [blocking]" : ""
      bullet "#{change.field}: #{render(change.before)} → #{render(change.after)}#{marker}"
    end

    bullet "no material field changed" if changes.empty?
    issues.each { |issue| bullet "current concern: #{issue}" }

    decision = blocking.empty? && issues.empty? ? "release" : "hold"

    field "decision",
          if decision == "release"
            "RELEASE — findings are unchanged and no concern is open"
          else
            "HOLD — a material change or open concern was found before payout"
          end

    # Both snapshots are kept. Neither overwrites the other.
    releases << payment.merge(
      decision: decision,
      prior_verification: stored,
      current_verification: {
        checked_at: Time.now.utc.iso8601,
        request_id: result.request_id,
        report_date: result.nonprofit.report_date,
        findings: current
      },
      changes: changes,
      blocking_changes: blocking.map(&:field)
    )
  end

  heading "Payment run"

  releases.each do |release|
    blocked_by = release[:blocking_changes]&.any? ? "blocked by: #{release[:blocking_changes].join(", ")}" : ""

    puts "  #{release[:payment_id]}  #{release[:ein]}  #{release[:decision].upcase.ljust(8)} #{blocked_by}".rstrip
  end

  held = releases.count { |release| release[:decision] == "hold" }

  puts
  field "released", releases.size - held
  field "held for review", held
  bullet "Each held payment retains the prior and the current verification evidence."
end

note "Recheck as close to the money movement as your workflow allows. A check from\n" \
     "onboarding proves what was true at onboarding, and a payout is a decision made\n" \
     "today."
