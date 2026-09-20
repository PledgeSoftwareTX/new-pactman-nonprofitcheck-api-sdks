# frozen_string_literal: true

# EX-19 — Bulk partial success and item-level errors.
#
# A bulk request where some EINs matched and some did not is a success. It comes
# back as HTTP 200 with organizations in `data` and the failures in `errors`.
#
# The successful records are fully usable. The failures keep the input EIN, so
# you can reconcile every row of your input against an outcome instead of
# discovering later that a grantee was silently skipped.
#
# Run:  PACTMAN_API_KEY=... bundle exec ruby examples/ex_19_bulk_partial_success.rb

require_relative "lib/fixture_api"
require_relative "lib/print"

NCP = Pactman::NonprofitCheckPlus
include Print

EINS = FixtureApi::EINS

FixtureApi.with_fixture_api do |client|
  submitted = [EINS[:public_charity], EINS[:no_record], EINS[:revoked], "123456789", EINS[:public_charity_second]]

  result = client.nonprofits.check_bulk(submitted)

  heading "Mixed outcome"
  field "HTTP status", result.status
  field "envelope code", result.raw["code"]
  field "envelope message", result.raw["message"]
  field "submitted", submitted.size
  field "matched", result.organizations.size
  field "item-level errors", result.errors.size
  field "not_found_eins", result.not_found_eins.join(", ")

  # Successful records are ordinary records. Nothing about a sibling failure
  # degrades them.
  heading "Successful records remain fully usable"

  result.organizations.each do |org|
    puts "  #{org.ein}  #{org.organization_name}"
    puts "    bmf_status=#{render(returned(NCP::Sources.bmf(org), :status))}  " \
         "pub78_verified=#{render(returned(NCP::Sources.pub78(org), :verified))}  " \
         "revocation_date=#{render(returned(NCP::Sources.aroe(org), :revocation_date))}"
  end

  heading "Failures, with their structured detail"

  result.errors.each do |detail|
    bullet "resource: #{detail.resource}"
    bullet "code: #{detail.code || "<none>"}"
    bullet "reason: #{detail.reason}"
    bullet "eins: #{JSON.generate(detail.eins)}"
  end

  # Reconcile every input against an outcome. This is the loop that keeps a
  # portfolio import honest.
  heading "Input reconciliation"

  matched = result.organizations.to_h { |org| [org.ein, org] }
  missing = result.not_found_eins.to_set
  unaccounted = []

  submitted.each_with_index do |ein, index|
    outcome = if matched.key?(ein)
                "matched"
              elsif missing.include?(ein)
                "no record — reported in errors"
              else
                unaccounted << ein
                "UNACCOUNTED FOR — do not treat as checked"
              end

    puts "  input[#{index}] #{ein}  #{outcome}"
  end

  puts
  field "unaccounted inputs", unaccounted.size

  bullet "An input with no matching record and no error is not a pass. Re-check it." unless unaccounted.empty?
end

note "An EIN the API has no record for is a gap in the data, not a negative finding\n" \
     "about the organization. Route it to review; do not record it as \"screened\"."
