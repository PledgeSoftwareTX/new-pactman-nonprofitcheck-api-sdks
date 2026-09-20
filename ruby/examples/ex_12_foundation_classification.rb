# frozen_string_literal: true

# EX-12 — Organization type and foundation classification.
#
# A grantmaker or DAF needs the classification on screen: public charity or
# private foundation, which 509(a) paragraph, which deductibility limitation. The
# SDK maps every one of those fields and declares none of them grant-eligible.
#
# Note which values are read from the API's own `*_description` fields rather
# than a local table. Descriptions the source supplies stay correct when the
# source changes; a lookup table in your repository does not.
#
# Run:  PACTMAN_API_KEY=... bundle exec ruby examples/ex_12_foundation_classification.rb

require_relative "lib/fixture_api"
require_relative "lib/irs_codes"
require_relative "lib/print"

NCP = Pactman::NonprofitCheckPlus
include Print

# What a grant officer sees. Every value is copied, none is computed.
def classification_panel(nonprofit)
  bmf = NCP::Sources.bmf(nonprofit)
  first_type = NCP::Sources.pub78(nonprofit)&.organization_types&.first

  {
    "subsection code" => returned(bmf, :subsection),
    "subsection description" => returned(bmf, :subsection_description),
    "foundation code" => returned(bmf, :foundation_code),
    "foundation code description" => returned(bmf, :foundation_code_description),
    "foundation type code" => returned(bmf, :foundation_type_code),
    "foundation type description" => returned(bmf, :foundation_type_description),
    "509(a) status" => returned(bmf, :foundation_509a_status),
    "Pub 78 deductibility" =>
      IrsCodes.describe_deductibility_status(returned(first_type, :deductibility_status_description)).summary
  }
end

FixtureApi.with_fixture_api do |client|
  [FixtureApi::EINS[:public_charity], FixtureApi::EINS[:private_foundation]].each do |ein|
    nonprofit = client.nonprofits.check(ein).nonprofit

    if nonprofit.nil?
      puts "No record for #{ein}."
      next
    end

    heading "#{nonprofit.organization_name} (#{nonprofit.ein})"

    classification_panel(nonprofit).each { |label, value| field label, value }

    heading "  organization_types"

    types = NCP::Sources.pub78(nonprofit)&.organization_types

    if types.nil? || types.empty?
      puts "    none returned"
    else
      types.each_with_index do |entry, index|
        puts "    [#{index}] status=#{entry&.deductibility_status_description} " \
             "limitation=#{entry&.deductibility_limitation}"
      end
    end

    # A DAF's own rules live here, and they are visibly the DAF's. A private
    # foundation grantee is not disqualified — it is routed differently, because
    # expenditure responsibility and the deductibility limit both change.
    private_foundation = NCP::Sources.bmf(nonprofit)&.foundation_type_code == "pf"

    puts
    field "this application routes to",
          if private_foundation
            "private-foundation workflow — expenditure responsibility review"
          else
            "standard public-charity workflow"
          end
  end
end

note "Displaying a classification is not asserting grant eligibility. The SDK reports\n" \
     "the IRS classification; whether a grant may be made, and on what terms, is your\n" \
     "grantmaking policy and your counsel's call."
