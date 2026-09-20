# frozen_string_literal: true

# EX-20 — Bulk batch-size validation.
#
# The batch limit is the server's. The SDK exports it as `MAX_BULK_EINS` and
# checks against it locally, so an over-limit batch fails in-process instead of
# spending a round trip to be told no.
#
# `MAX_BULK_EINS` is declared once in the SDK. Reference it — do not copy the
# number into your own constants file, where it will outlive the server's.
#
# Run:  PACTMAN_API_KEY=... bundle exec ruby examples/ex_20_bulk_batch_limits.rb

require_relative "lib/fixture_api"
require_relative "lib/print"

NCP = Pactman::NonprofitCheckPlus
include Print

# Fills a batch with well-formed EINs, so only the size is under test.
def batch_of_size(size)
  Array.new(size) { |index| (100_000_000 + index).to_s }
end

def show_rejection(error)
  field "class", error.class.name
  field "origin", error.origin.inspect
  field "message", error.message
  field "request sent", "no"
end

FixtureApi.with_fixture_api do |client|
  heading "The authoritative limit"
  field "MAX_BULK_EINS", NCP::MAX_BULK_EINS
  bullet "Exported by the SDK, mirroring the server-side maximum."
  bullet "Referenced here; not redeclared."

  heading "Empty collection"

  begin
    client.nonprofits.check_bulk([])
    puts "  Unexpectedly accepted."
  rescue NCP::ValidationError => e
    show_rejection(e)
  end

  heading "Over-limit collection (#{NCP::MAX_BULK_EINS + 1} EINs)"

  begin
    client.nonprofits.check_bulk(batch_of_size(NCP::MAX_BULK_EINS + 1))
    puts "  Unexpectedly accepted."
  rescue NCP::ValidationError => e
    show_rejection(e)
  end

  heading "At the limit (#{NCP::MAX_BULK_EINS} EINs)"

  # Accepted locally and sent. Most of these EINs have no record, so this comes
  # back as a partial success — the size was never the problem.
  at_limit = [FixtureApi::EINS[:public_charity], *batch_of_size(NCP::MAX_BULK_EINS - 1)]
  result = client.nonprofits.check_bulk(at_limit)

  field "EINs sent", at_limit.size
  field "status", result.status
  field "organizations returned", result.organizations.size
  field "not_found_eins", result.not_found_eins.size

  # If the server ever tightens its limit below the SDK's, the local check will
  # pass and the server will answer 400. That message is authoritative; surface it
  # rather than trusting the constant.
  heading "If the server disagrees with the constant"
  bullet "A server-side rejection arrives as #{NCP::BadRequestError.name}."
  bullet "`api_errors.map(&:reason)` carries the limit the server actually enforces."
  bullet "Rescue it and log the reason verbatim."

  # Chunking is your decision, not the SDK's: it refuses to split a batch,
  # because doing so quietly turns one billable request into several.
  heading "Splitting a larger list"

  large_list = batch_of_size(120)
  batches = large_list.each_slice(NCP::MAX_BULK_EINS).to_a

  field "input size", large_list.size
  field "batches", batches.size
  field "batch sizes", batches.map(&:size).join(", ")
  bullet "The SDK never chunks for you — each batch below is a request you chose to make."
end

note "One constant, referenced everywhere. A hardcoded 50 scattered through a codebase\n" \
     "is a migration waiting to be missed."
