# frozen_string_literal: true

# EX-30 — Scheduled portfolio re-verification and audit trail.
#
# A platform or consultant rechecks every onboarded organization on its own
# schedule, records what changed in status, revocation, reinstatement, OFAC,
# identity, classification and data freshness, and writes an audit entry it can
# still explain a year later.
#
# What makes an audit trail useful is not the outcome — it is the evidence next to
# the outcome: when the check ran, which request it was, what each source said,
# which policy version applied, and what changed since last time.
#
# Run:  PACTMAN_API_KEY=... bundle exec ruby examples/ex_30_portfolio_reverification.rb

require "time"
require_relative "lib/fixture_api"
require_relative "lib/print"
require_relative "lib/screening"

NCP = Pactman::NonprofitCheckPlus
include Print

EINS = FixtureApi::EINS

# Identify the rules that produced an outcome, so old entries stay readable.
POLICY_VERSION = "2026.02-portfolio-rev3"
RE_REVIEW_INTERVAL_DAYS = 90

# The portfolio, with whatever the last run stored.
portfolio = [
  { ein: EINS[:public_charity], onboarded_at: "2025-11-02", last_findings: nil },
  { ein: EINS[:public_charity_second], onboarded_at: "2025-12-14", last_findings: nil },
  { ein: EINS[:private_foundation], onboarded_at: "2026-01-09", last_findings: nil },
  {
    ein: EINS[:reinstated],
    onboarded_at: "2025-09-30",
    # Stored at the previous run, before the reinstatement was published.
    last_findings: {
      "organization_name" => "SECOND CHANCE EXAMPLE ALLIANCE",
      "bmf_status" => true,
      "exempt_status_code" => "01",
      "pub78_verified" => true,
      "revocation_code" => "01",
      "revocation_date" => "2/06/2022 9:41:03 PM",
      "reinstatement_date" => nil,
      "ofac_state" => "no_match",
      "irs_bmf_pub78_conflict" => false,
      "foundation_type_code" => "pc",
      "subsection_description" => "501(c)(3) Public Charity"
    }
  },
  { ein: EINS[:ofac_match], onboarded_at: "2026-02-01", last_findings: nil },
  { ein: EINS[:no_record], onboarded_at: "2025-08-21", last_findings: nil }
]

def outcome_for(findings, changes)
  return "suspend" if findings["ofac_state"] == "match"
  return "suspend" if findings["revoked"] && !findings["reinstated"]
  return "review" if changes.any? || Screening.concerns(findings).any?

  "retain"
end

FixtureApi.with_fixture_api do |client|
  run_started_at = Time.now
  audit_log = []

  # Split into requests the server will accept. The limit is the SDK's constant,
  # never a number copied from the documentation.
  batches = portfolio.map { |entry| entry[:ein] }.each_slice(NCP::MAX_BULK_EINS).to_a

  heading "Re-verification run"
  field "policy version", POLICY_VERSION
  field "interval (days)", RE_REVIEW_INTERVAL_DAYS
  field "organizations", portfolio.size
  field "batches", batches.size
  field "started at", run_started_at.utc.iso8601

  records = {}
  last_check_count = nil

  batches.each_with_index do |eins, index|
    result = client.nonprofits.check_bulk(eins)
    last_check_count = result.check_count

    result.organizations.each do |org|
      records[org.ein] = { org: org, request_id: result.request_id, status: result.status }
    end

    # An EIN that produced no record is recorded as unverified, not as clean.
    result.not_found_eins.each do |missing|
      records[missing] = { org: nil, request_id: result.request_id, status: result.status }
    end

    puts "  batch #{index + 1}: sent #{eins.size}, matched #{result.organizations.size}, " \
         "missing #{result.not_found_eins.size}, request #{result.request_id}"
  end

  portfolio.each do |entry|
    record = records[entry[:ein]]

    heading "#{entry[:ein]} (onboarded #{entry[:onboarded_at]})"

    if record.nil? || record[:org].nil?
      field "outcome", "review"
      bullet "No record returned. The organization is unverified this cycle, not cleared."

      audit_log << { ein: entry[:ein], checked_at: run_started_at.utc.iso8601, request_id: record&.fetch(:request_id),
                     policy_version: POLICY_VERSION, outcome: "review", reason: "no_record_returned", changes: [],
                     findings: nil }
      next
    end

    findings = Screening.collect_findings(record[:org], run_started_at)
    changes = Screening.diff_findings(entry[:last_findings], findings)
    open_concerns = Screening.concerns(findings)

    # A first run has nothing to compare against; say so rather than reporting
    # every field as "changed".
    baseline = entry[:last_findings].nil?

    field "organization", findings["organization_name"]
    field "baseline run", baseline
    field "changes since last run", baseline ? "<no prior snapshot>" : changes.size

    unless baseline
      changes.each do |change|
        bullet "#{change.field}: #{render(change.before)} → #{render(change.after)}"
      end
    end

    field "bmf_status", findings["bmf_status"]
    field "pub78_verified", findings["pub78_verified"]
    field "revocation_date", findings["revocation_date"]
    field "reinstatement_date", findings["reinstatement_date"]
    field "ofac state", findings["ofac_state"]
    field "conflict flag", findings["irs_bmf_pub78_conflict"]
    field "classification", findings["subsection_description"]
    field "oldest source (days)", findings["oldest_source_age_days"]
    field "report_date", findings["report_date"]

    open_concerns.each { |concern| bullet "concern: #{concern}" }

    outcome = outcome_for(findings, baseline ? [] : changes)

    field "outcome", outcome

    # The entry a consultant can produce when asked, months later, why an
    # organization was suspended or retained.
    audit_log << {
      ein: entry[:ein],
      checked_at: run_started_at.utc.iso8601,
      request_id: record[:request_id],
      http_status: record[:status],
      policy_version: POLICY_VERSION,
      outcome: outcome,
      concerns: open_concerns,
      changes: baseline ? [] : changes.map(&:to_h),
      findings: findings,
      next_review_due: (run_started_at + (RE_REVIEW_INTERVAL_DAYS * 86_400)).utc.iso8601
    }

    # Carry the snapshot forward, so the next run has something to diff against.
    entry[:last_findings] = findings
  end

  heading "Audit log"
  puts "  #{"ein".ljust(12)} #{"outcome".ljust(9)} #{"changes".ljust(8)} request"

  audit_log.each do |entry|
    puts "  #{entry[:ein].ljust(12)} #{entry[:outcome].ljust(9)} #{entry[:changes].size.to_s.ljust(8)} " \
         "#{entry[:request_id] || "<none>"}"
  end

  heading "Run summary"
  field "entries written", audit_log.size
  field("suspended", audit_log.count { |entry| entry[:outcome] == "suspend" })
  field("to review", audit_log.count { |entry| entry[:outcome] == "review" })
  field("retained", audit_log.count { |entry| entry[:outcome] == "retain" })
  field "checks used this cycle", last_check_count
  field "next run due", audit_log.find { |entry| entry[:next_review_due] }&.fetch(:next_review_due)

  bullet "Request identifiers are stored; API keys are not, and never appear here."
end

note "The audit trail records what the sources said and which policy read them. It is\n" \
     "evidence of a process, not a legal determination — the SDK supplies the former\n" \
     "and takes no position on the latter."
