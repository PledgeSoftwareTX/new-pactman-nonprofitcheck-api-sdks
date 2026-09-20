# frozen_string_literal: true

# EX-18 — Bulk input order and duplicate EINs.
#
# Three things worth knowing before you zip a bulk response against your input:
#
#   1. The SDK sends your EINs in the order you supplied them, duplicates
#      included. It does not reorder and it does not deduplicate.
#   2. The API matches by set membership. Response order is not guaranteed to
#      follow request order, and a duplicated EIN comes back once. Index results
#      by EIN; never pair them positionally.
#   3. `nonprofit_check_count` is not the count of unique EINs you sent. Do not
#      reconstruct usage from your input — read the number the API reports.
#
# Run:  PACTMAN_API_KEY=... bundle exec ruby examples/ex_18_bulk_order_and_duplicates.rb

require_relative "lib/fixture_api"
require_relative "lib/print"

include Print

EINS = FixtureApi::EINS

def delta(before, after)
  before.nil? || after.nil? ? "<not reported>" : after - before
end

FixtureApi.with_fixture_api do |client|
  # Deliberately unsorted, with one EIN repeated twice.
  requested = [EINS[:public_charity_second], EINS[:public_charity], EINS[:public_charity_second],
               EINS[:private_foundation]]

  heading "Sent as supplied — no reordering, no deduplication"
  requested.each_with_index { |ein, index| bullet "[#{index}] #{ein}" }
  field "unique EINs", requested.uniq.size
  field "EINs sent", requested.size

  before = client.nonprofits.check(EINS[:public_charity])
  result = client.nonprofits.check_bulk(requested)

  heading "Returned"
  result.organizations.each_with_index { |org, index| bullet "[#{index}] #{org.ein}  #{org.organization_name}" }

  returned_order = result.organizations.map(&:ein)

  field "response length", returned_order.size
  field "request length", requested.size
  field "positional pairing valid", returned_order == requested
  field "matches request order (deduped)", returned_order == requested.uniq

  # The correct way to consume a bulk response.
  by_ein = result.organizations.to_h { |org| [org.ein, org] }

  heading "Indexed by EIN — the pairing that always holds"

  requested.each_with_index do |ein, index|
    org = by_ein[ein]
    duplicate = requested.index(ein) == index ? "" : "   (duplicate of an earlier input)"

    puts "  input[#{index}] #{ein} → #{org ? org.organization_name : "no record returned"}#{duplicate}"
  end

  heading "Usage is reported, not inferred"
  field "unique EINs submitted", requested.uniq.size
  field "total EINs submitted", requested.size
  field "organizations returned", result.organizations.size
  field "check_count before this call", before.check_count
  field "check_count after this call", result.check_count
  field "delta", delta(before.check_count, result.check_count)

  bullet "Each submitted EIN is billable, duplicates included."
  bullet "The delta above is the authority on what this request consumed."
  bullet "Deriving usage from your unique-input count will disagree with the invoice."

  # Opt in when duplicates are an artifact of your data rather than intent.
  heading "Opting in to deduplication"

  deduped = client.nonprofits.check_bulk(requested, dedupe: true)

  field "EINs sent after dedupe", requested.uniq.size
  field "organizations returned", deduped.organizations.size
  field "check_count", deduped.check_count
  field "delta", delta(result.check_count, deduped.check_count)
end

note "Deduplication is off by default because collapsing a list silently would\n" \
     "misreport what was checked. Pass `dedupe: true` when you mean it."
