# frozen_string_literal: true

# EX-17 — Bulk screening of a grantee or nonprofit list.
#
# The shape of the work a grantmaker, DAF, employee-giving platform or migrating
# consultant actually does: hand the API a list of EINs, walk the organizations
# that came back, and keep the response-level metadata.
#
# One bulk request is one round trip and one rate-limit slot. Prefer it to a loop
# of single checks.
#
# Run:  PACTMAN_API_KEY=... bundle exec ruby examples/ex_17_bulk_screening.rb

require_relative "lib/fixture_api"
require_relative "lib/print"

NCP = Pactman::NonprofitCheckPlus
include Print

EINS = FixtureApi::EINS

# A grantee portfolio as it might arrive from a spreadsheet import.
PORTFOLIO = [
  { ein: EINS[:public_charity], grantee: "Meals Today" },
  { ein: EINS[:public_charity_second], grantee: "Aborjaily Fund" },
  { ein: EINS[:private_foundation], grantee: "Hartwell Family Foundation" },
  { ein: EINS[:revoked], grantee: "Lapsed Filings Society" },
  { ein: EINS[:no_record], grantee: "Unknown Org From The Import" }
].freeze

def ofac_label(ofac)
  return "unscreened" if ofac.nil? || ofac.status.nil?

  ofac.status.include?("UID:") ? "POSSIBLE MATCH" : "no match"
end

FixtureApi.with_fixture_api do |client|
  eins = PORTFOLIO.map { |entry| entry[:ein] }

  heading "Screening #{eins.size} EINs (server limit is #{NCP::MAX_BULK_EINS} per request)"

  result = client.nonprofits.check_bulk(eins)

  # Response-level envelope fields, all reachable.
  field "status", result.status
  field 'raw["code"]', result.raw["code"]
  field 'raw["message"]', result.raw["message"]
  field "timeTaken (ms)", result.time_taken_ms
  field "nonprofit_check_count", result.check_count
  field "organizations returned", result.organizations.size
  field "item-level errors", result.errors.size
  field "not_found_eins", result.not_found_eins.empty? ? "<none>" : result.not_found_eins.join(", ")

  # Index by EIN. The response is a set of matched records, not a row-for-row
  # answer to your input list — see ex_18.
  by_ein = result.organizations.to_h { |org| [org.ein, org] }

  heading "Organization-level results"

  PORTFOLIO.each do |entry|
    org = by_ein[entry[:ein]]

    if org.nil?
      puts "  #{entry[:ein]}  #{entry[:grantee].ljust(28)} no record returned"
      next
    end

    bmf = NCP::Sources.bmf(org)
    pub78 = NCP::Sources.pub78(org)
    aroe = NCP::Sources.aroe(org)

    puts "  #{org.ein}  #{org.organization_name.to_s[0, 28].ljust(28)} " \
         "bmf=#{render(returned(bmf, :status))}  pub78=#{render(returned(pub78, :verified))}  " \
         "revoked=#{!(aroe.nil? || aroe.revocation_date.nil?)}  " \
         "ofac=#{ofac_label(NCP::Sources.ofac(org))}  " \
         "conflict=#{render(returned(org, :irs_bmf_pub78_conflict))}"
  end

  heading "Item-level errors, verbatim"

  result.errors.each do |detail|
    puts "  resource=#{detail.resource}"
    puts "  code=#{detail.code || "<none>"}"
    puts "  reason=#{detail.reason}"
    puts "  eins=#{JSON.generate(detail.eins)}"
  end

  puts "  none" if result.errors.empty?
end

note "This is a screening pass, not an approval pass. Each row above is source data\n" \
     "for your grant policy to act on — ex_27 shows one worked routing."
