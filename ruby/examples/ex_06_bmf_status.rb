# frozen_string_literal: true

# EX-06 — IRS Business Master File status inspection.
#
# Reads every BMF field the response carries: status, identity, subsection,
# exemption, ruling and foundation classification.
#
# There is no `exempt?` here and none in the SDK. `bmf_status` is one source's
# answer to one question; an organization can be listed in the BMF and still be
# revoked, sanctioned, or in conflict with Publication 78.
#
# Run:  PACTMAN_API_KEY=... bundle exec ruby examples/ex_06_bmf_status.rb [EIN]

require_relative "lib/client"
require_relative "lib/fixture_api"
require_relative "lib/irs_codes"
require_relative "lib/print"

NCP = Pactman::NonprofitCheckPlus
include Print

client = ExampleClient.create_client
ein = ARGV.fetch(0, FixtureApi::EINS[:public_charity])

nonprofit = client.nonprofits.check(ein).nonprofit

if nonprofit.nil?
  puts "No record for EIN #{ein}."
  exit 0
end

bmf = NCP::Sources.bmf(nonprofit)

if bmf.nil?
  # Not "not in the BMF" — the API returned no BMF fields at all. Those are
  # different findings and this example refuses to merge them.
  puts "The response carried no Business Master File data for this organization."
  puts "That is an absence of evidence, not a negative finding. Route it to review."
  exit 0
end

heading "BMF status"
field "bmf_status", returned(bmf, :status)
field "exempt_status_code", IrsCodes.describe_exempt_status(returned(bmf, :exempt_status_code)).summary
field "most_recent_bmf", returned(bmf, :most_recent)

heading "BMF identity"
field "bmf_organization_name", returned(bmf, :organization_name)
field "bmf_ein", returned(bmf, :ein)
field "bmf_church_message", returned(bmf, :church_message)

heading "Subsection"
field "bmf_subsection", returned(bmf, :subsection)
field "subsection_description", returned(bmf, :subsection_description)

heading "Exemption and ruling"
field "ruling date (year-month)", IrsCodes.format_ruling_date(returned(bmf, :ruling_month), returned(bmf, :ruling_year))
field "ruling_month", returned(bmf, :ruling_month)
field "ruling_year", returned(bmf, :ruling_year)
field "group_exemption", returned(bmf, :group_exemption)

heading "Foundation classification"
field "foundation_code", returned(bmf, :foundation_code)
field "foundation_code_description", returned(bmf, :foundation_code_description)
field "foundation_type_code", returned(bmf, :foundation_type_code)
field "foundation_type_description", returned(bmf, :foundation_type_description)
field "foundation_509a_status", returned(bmf, :foundation_509a_status)

heading "Filing requirements"
field "filing_req_code", IrsCodes.describe_filing_requirement(returned(bmf, :filing_req_code)).summary

# Every value above came straight off the response. Turning them into an
# approve/decline decision is the next step, and it belongs in your policy code
# — see ex_26 for a worked routing example.
note "The BMF is one of four sources this API reports. Reading it in isolation is how\n" \
     "a revoked or sanctioned organization passes a check: see ex_08 and ex_10."
