# frozen_string_literal: true

# EX-27 — DAF grant-recommendation screening.
#
# A donor recommends a grant. Before the recommendation advances, the sponsoring
# organization screens the grantee, shows the tax and foundation classification
# to the grants team, and sends anything revoked, sanctioned, conflicting or
# ambiguous to review.
#
# A DAF's rules are stricter than a donation platform's — compare the policy block
# here with the one in ex_26. Same API data, different obligations, different
# outcomes. That difference is precisely why the SDK does not decide.
#
# Run:  PACTMAN_API_KEY=... bundle exec ruby examples/ex_27_daf_grant_screening.rb

require "time"
require_relative "lib/fixture_api"
require_relative "lib/print"
require_relative "lib/screening"

include Print

EINS = FixtureApi::EINS

# This sponsoring organization's rules. Yours will differ.
POLICY = {
  stale_after_days: 90,
  # A private foundation grantee is not refused — it takes a different path,
  # because expenditure responsibility applies.
  private_foundation_requires_expenditure_responsibility: true,
  # Anything the screen could not establish stops the recommendation.
  treat_unknown_as_blocking: true
}.freeze

RECOMMENDATIONS = [
  { grant_id: "G-1001", ein: EINS[:public_charity], amount: 25_000, donor: "Fund 88" },
  { grant_id: "G-1002", ein: EINS[:private_foundation], amount: 10_000, donor: "Fund 88" },
  { grant_id: "G-1003", ein: EINS[:revoked], amount: 5_000, donor: "Fund 14" },
  { grant_id: "G-1004", ein: EINS[:ofac_match], amount: 40_000, donor: "Fund 14" },
  { grant_id: "G-1005", ein: EINS[:conflicted], amount: 7_500, donor: "Fund 03" },
  { grant_id: "G-1006", ein: EINS[:reinstated], amount: 15_000, donor: "Fund 03" },
  { grant_id: "G-1007", ein: EINS[:sparse_identity], amount: 2_000, donor: "Fund 21" }
].freeze

Screened = Data.define(:outcome, :queue, :issues)

def money(amount)
  "$#{amount.to_s.reverse.scan(/\d{1,3}/).join(",").reverse}"
end

def screen(findings)
  issues = Screening.concerns(findings, stale_after_days: POLICY[:stale_after_days])

  return Screened.new("blocked", "sanctions_review", issues) if findings["ofac_state"] == "match"
  return Screened.new("blocked", "tax_status_review", issues) if findings["revoked"] && !findings["reinstated"]
  return Screened.new("held", "source_conflict_review", issues) if findings["irs_bmf_pub78_conflict"] == true
  return Screened.new("held", "grants_review", issues) if POLICY[:treat_unknown_as_blocking] && !issues.empty?

  if findings["foundation_type_code"] == "pf" && POLICY[:private_foundation_requires_expenditure_responsibility]
    return Screened.new("held", "expenditure_responsibility", issues)
  end

  Screened.new("advanced", "ready_for_approval", issues)
end

FixtureApi.with_fixture_api do |client|
  # One bulk call for the whole recommendation batch.
  result = client.nonprofits.check_bulk(RECOMMENDATIONS.map { |entry| entry[:ein] })
  by_ein = result.organizations.to_h { |org| [org.ein, org] }

  heading "Screening batch"
  field "recommendations", RECOMMENDATIONS.size
  field "records returned", result.organizations.size
  field "no record for", result.not_found_eins.empty? ? "<none>" : result.not_found_eins.join(", ")
  field "checks used this cycle", result.check_count

  decisions = []

  RECOMMENDATIONS.each do |recommendation|
    nonprofit = by_ein[recommendation[:ein]]

    heading "#{recommendation[:grant_id]} — #{money(recommendation[:amount])} to #{recommendation[:ein]}"

    if nonprofit.nil?
      field "outcome", "held"
      field "queue", "grants_review"
      bullet "No record was returned for this EIN. Nothing was verified."
      decisions << recommendation.merge(outcome: "held", queue: "grants_review")
      next
    end

    findings = Screening.collect_findings(nonprofit)
    screened = screen(findings)

    # What the grants team sees on screen.
    field "grantee", findings["organization_name"]
    field "also known as", findings["organization_name_aka"]
    field "subsection", findings["subsection_description"]
    field "foundation type", findings["foundation_type_description"]
    field "foundation type code", findings["foundation_type_code"]
    field "deductibility limitations",
          findings["deductibility_limitations"].empty? ? "<none>" : findings["deductibility_limitations"].join(", ")
    field "bmf_status", findings["bmf_status"]
    field "pub78_verified", findings["pub78_verified"]
    field "revocation_date", findings["revocation_date"]
    field "reinstatement_date", findings["reinstatement_date"]
    field "ofac state", findings["ofac_state"]
    field "conflict flag", findings["irs_bmf_pub78_conflict"]
    field "oldest source (days)", findings["oldest_source_age_days"]

    field "outcome", screened.outcome
    field "queue", screened.queue
    screened.issues.each { |issue| bullet issue }

    decisions << recommendation.merge(
      outcome: screened.outcome,
      queue: screened.queue,
      screened_at: Time.now.utc.iso8601,
      request_id: result.request_id,
      source_findings: findings
    )
  end

  heading "Recommendation queue"

  decisions.each do |decision|
    puts "  #{decision[:grant_id]}  #{decision[:ein]}  #{decision[:outcome].ljust(9)} → #{decision[:queue]}"
  end

  advanced = decisions.count { |decision| decision[:outcome] == "advanced" }

  puts
  field "advanced to approval", advanced
  field "held or blocked", decisions.size - advanced
end

note "Advancing a recommendation is a step in this DAF's process, not a legal approval\n" \
     "of the grant. The findings recorded above are the source data the decision\n" \
     "rested on; the determination itself remains the sponsoring organization's."
