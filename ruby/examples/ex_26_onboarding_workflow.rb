# frozen_string_literal: true

# EX-26 — Donation-platform onboarding workflow.
#
# The end-to-end shape: an applicant supplies an EIN, a legal name and an address;
# one check gathers BMF, Publication 78, revocation, OFAC, conflict and freshness
# findings; the platform routes the applicant.
#
# The routing rules below belong to this fictional platform. Read them as an
# illustration of where your policy lives, not as a policy to adopt. The SDK
# contributes evidence and stops there — it never produces the decision.
#
# Run:  PACTMAN_API_KEY=... bundle exec ruby examples/ex_26_onboarding_workflow.rb

require "time"
require_relative "lib/fixture_api"
require_relative "lib/matching"
require_relative "lib/print"
require_relative "lib/screening"

NCP = Pactman::NonprofitCheckPlus
include Print

EINS = FixtureApi::EINS

# This platform's rules, in one place, reviewable by its compliance team.
POLICY = {
  stale_after_days: 120,
  require_pub78_listing: true,
  address_components: %w[address_line1 city state zip]
}.freeze

WESTFIELD = { "address_line1" => "50 Lowell Ave", "city" => "Westfield", "state" => "MA", "zip" => "01085" }.freeze

APPLICANTS = [
  { ein: EINS[:public_charity], legal_name: "Meals Today Example Nonprofit, Inc.", address: WESTFIELD },
  { ein: EINS[:revoked], legal_name: "Lapsed Filings Example Society", address: WESTFIELD },
  { ein: EINS[:ofac_match], legal_name: "Overseas Relief Example Fund", address: WESTFIELD },
  { ein: EINS[:conflicted], legal_name: "Crosscheck Example Institute", address: WESTFIELD },
  { ein: EINS[:no_record], legal_name: "Unlisted Example Org",
    address: { "address_line1" => "1 Main St", "city" => "Boston", "state" => "MA", "zip" => "02108" } }
].freeze

Decision = Data.define(:decision, :reasons)

# Applies POLICY to the gathered evidence. Returns a route and its reasons.
def route(findings, name_comparison, address_outcomes, issues)
  reasons = issues.dup

  if findings["revoked"] && !findings["reinstated"]
    return Decision.new("reject", ["Exemption revoked with no reinstatement.", *reasons])
  end

  return Decision.new("reject", ["Possible OFAC SDN match.", *reasons]) if findings["ofac_state"] == "match"

  unless Matching.agreement?(name_comparison.outcome)
    reasons << "Submitted name did not match an IRS-held name (#{name_comparison.outcome})."
  end

  address_conflicts = POLICY[:address_components].select { |component| address_outcomes[component] == "mismatch" }
  reasons << "Address components disagree: #{address_conflicts.join(", ")}." unless address_conflicts.empty?

  if POLICY[:require_pub78_listing] && findings["pub78_verified"] != true
    reasons << "Not listed in Publication 78, which this platform requires."
  end

  if reasons.empty?
    Decision.new("approve", ["Every check this platform requires was satisfied."])
  else
    Decision.new("manual_review", reasons)
  end
end

FixtureApi.with_fixture_api do |client|
  outcomes = []

  APPLICANTS.each do |applicant|
    heading "Applicant #{applicant[:ein]} — #{applicant[:legal_name]}"

    begin
      result = client.nonprofits.check(applicant[:ein])
    rescue NCP::Error => e
      # A failed lookup is not a rejection. Nothing was learned, so nothing can be
      # concluded — the applicant waits, they are not turned away.
      field "lookup", "failed: #{e.class.name.split("::").last} (#{e.category})"
      field "decision", "manual_review — the check could not be completed"
      outcomes << { ein: applicant[:ein], decision: "manual_review" }
      next
    end

    nonprofit = result.nonprofit

    if nonprofit.nil?
      field "decision", "manual_review — no record returned for this EIN"
      outcomes << { ein: applicant[:ein], decision: "manual_review" }
      next
    end

    findings = Screening.collect_findings(nonprofit)
    issues = Screening.concerns(findings, stale_after_days: POLICY[:stale_after_days])

    name_comparison = Matching.compare_name(
      applicant[:legal_name],
      "organization_name" => nonprofit.organization_name,
      "organization_name_aka" => nonprofit.organization_name_aka
    )

    address_outcomes = POLICY[:address_components].to_h do |component|
      normalize = component == "zip" ? Matching.method(:normalize_zip) : Matching.method(:normalize_address_line)

      [component,
       Matching.compare_address_field(applicant[:address][component], nonprofit[component], normalize).outcome]
    end

    field "IRS name", nonprofit.organization_name
    field "name comparison", name_comparison.outcome
    field "address comparison", address_outcomes.map { |component, outcome| "#{component}=#{outcome}" }.join(" ")
    field "bmf_status", findings["bmf_status"]
    field "pub78_verified", findings["pub78_verified"]
    field "revoked / reinstated", "#{findings["revoked"]} / #{findings["reinstated"]}"
    field "ofac state", findings["ofac_state"]
    field "irs_bmf_pub78_conflict", findings["irs_bmf_pub78_conflict"]
    field "oldest source age (days)", findings["oldest_source_age_days"]

    decision = route(findings, name_comparison, address_outcomes, issues)

    field "decision", decision.decision
    decision.reasons.each { |reason| bullet reason }

    # The record that makes the decision explainable months later.
    outcomes << {
      ein: applicant[:ein],
      decision: decision.decision,
      reasons: decision.reasons,
      checked_at: Time.now.utc.iso8601,
      request_id: result.request_id,
      findings: findings
    }
  end

  heading "Onboarding queue"

  outcomes.each { |outcome| puts "  #{outcome[:ein]}  #{outcome[:decision]}" }
end

note "The platform decided; the SDK did not. Nothing in this gem returns approve,\n" \
     "reject, eligible or safe, and no combination of the fields above constitutes a\n" \
     "compliance determination on its own."
