# frozen_string_literal: true

# EX-13 — Filing and exemption metadata.
#
# Displays `filing_req_code`, the exemption status, the ruling date and the other
# IRS classification codes on the response.
#
# Two rules apply to every code below:
#
#   - the raw value is preserved exactly as the API sent it, `null` included
#   - a code is only labelled through a documented table with an unknown-value
#     fallback, so a value added by the IRS reads as "unrecognized", never as
#     `nil` and never as the wrong label
#
# Run:  PACTMAN_API_KEY=... bundle exec ruby examples/ex_13_filing_exemption_metadata.rb

require_relative "lib/fixture_api"
require_relative "lib/irs_codes"
require_relative "lib/print"

NCP = Pactman::NonprofitCheckPlus
include Print

def code_row(label, mapped)
  puts "  #{label.ljust(28)} raw=#{render(mapped.code).ljust(10)} known=#{mapped.known.to_s.ljust(6)} " \
       "#{mapped.description || mapped.summary}"
end

FixtureApi.with_fixture_api do |client|
  [
    ["public charity", FixtureApi::EINS[:public_charity]],
    ["private foundation", FixtureApi::EINS[:private_foundation]],
    ["revoked — status code differs", FixtureApi::EINS[:revoked]],
    ["sparse — several codes are null", FixtureApi::EINS[:sparse_identity]]
  ].each do |label, ein|
    nonprofit = client.nonprofits.check(ein).nonprofit

    if nonprofit.nil?
      puts "No record for #{ein}."
      next
    end

    bmf = NCP::Sources.bmf(nonprofit)

    heading "#{label} — #{nonprofit.organization_name}"

    code_row "filing_req_code", IrsCodes.describe_filing_requirement(returned(bmf, :filing_req_code))
    code_row "exempt_status_code", IrsCodes.describe_exempt_status(returned(bmf, :exempt_status_code))

    # Codes the API already describes for you. Read the description it sends; do
    # not shadow it with a local table that will drift.
    field "bmf_subsection", returned(bmf, :subsection)
    field "subsection_description", returned(bmf, :subsection_description)
    field "foundation_code", returned(bmf, :foundation_code)
    field "foundation_code_description", returned(bmf, :foundation_code_description)

    field "ruling_month", returned(bmf, :ruling_month)
    field "ruling_year", returned(bmf, :ruling_year)
    field "ruling date", IrsCodes.format_ruling_date(returned(bmf, :ruling_month), returned(bmf, :ruling_year))
    field "group_exemption", returned(bmf, :group_exemption)
    field "revocation_code", returned(nonprofit, :revocation_code)
  end

  # An unknown code must survive the round trip intact. This is the case that
  # breaks applications which map codes eagerly into an enum.
  nonprofit = client.nonprofits.check(FixtureApi::EINS[:future_fields]).nonprofit

  heading "A code this SDK version has never seen"
  field "foundation_type_code", returned(nonprofit, :foundation_type_code)
  field "foundation_type_description", returned(nonprofit, :foundation_type_description)
  code_row "exempt_status_code (forced)", IrsCodes.describe_exempt_status("99")
  field "value preserved", nonprofit&.foundation_type_code == "zz"
end

note "Never coerce an unrecognized code to a default. \"Unknown\" is a real state and\n" \
     "usually means review, not approval — see ex_25 for the same rule applied to\n" \
     "whole fields the SDK does not know about yet."
