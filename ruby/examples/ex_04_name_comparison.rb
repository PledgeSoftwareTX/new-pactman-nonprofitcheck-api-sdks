# frozen_string_literal: true

# EX-04 — Applicant name comparison.
#
# An applicant types a name during onboarding. The API returns the name IRS
# records hold, plus an alternate name when one exists. Punctuation, casing and
# abbreviation differences are normal; they are not evidence of fraud.
#
# The SDK deliberately has no `names_match?`. What counts as a match is your
# policy, so the comparison lives here, in customer code.
#
# Run:  PACTMAN_API_KEY=... bundle exec ruby examples/ex_04_name_comparison.rb

require_relative "lib/client"
require_relative "lib/fixture_api"
require_relative "lib/matching"
require_relative "lib/print"

include Print

client = ExampleClient.create_client
public_charity = FixtureApi::EINS[:public_charity]

# Three applicants against the same organization: a formatting difference, an
# abbreviation difference, and a genuinely different name.
applicants = [
  { ein: public_charity, legal_name: "Meals Today Example Nonprofit" },
  { ein: public_charity, legal_name: "meals today example nonprofit, inc." },
  { ein: public_charity, legal_name: "Springfield Animal Rescue" }
]

# Your routing policy, not the SDK's.
def route_name_outcome(outcome)
  case outcome
  when "exact", "normalized"
    "continue — the submitted name agrees with an IRS-held name"
  when "not_returned"
    "manual review — the API returned no name to compare against"
  else
    "manual review — a human decides whether this is a rebrand, a typo, or the wrong EIN"
  end
end

applicants.each do |applicant|
  nonprofit = client.nonprofits.check(applicant[:ein]).nonprofit

  if nonprofit.nil?
    puts "No record for #{applicant[:ein]}."
    next
  end

  comparison = Matching.compare_name(
    applicant[:legal_name],
    "organization_name" => nonprofit.organization_name,
    "organization_name_aka" => nonprofit.organization_name_aka
  )

  heading "Applicant: #{applicant[:legal_name]}"
  field "organization_name", nonprofit.organization_name
  field "organization_name_aka", nonprofit.organization_name_aka
  field "normalized applicant", comparison.submitted

  comparison.candidates.each do |candidate|
    bullet "#{candidate.source} normalizes to \"#{candidate.normalized}\""
  end

  field "outcome", comparison.outcome
  field "matched field", comparison.matched_field
  field "agreement", Matching.agreement?(comparison.outcome)
  field "routed to", route_name_outcome(comparison.outcome)
end

note "A name mismatch is a reason to look, not a finding. Organizations rebrand, file\n" \
     "under a parent, and appear in IRS data under a name no donor would recognize.\n" \
     "This example routes disagreement to review; it never labels an applicant."
