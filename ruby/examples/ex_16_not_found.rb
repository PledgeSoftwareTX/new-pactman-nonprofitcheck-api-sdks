# frozen_string_literal: true

# EX-16 — EIN not found, and application-level failures.
#
# A well-formed EIN with no matching record is a normal outcome, not a bug. The
# single endpoint answers HTTP 404, which the SDK raises as `NotFoundError` — a
# subclass of `ApiError`, so a handler can rescue the specific case or the general
# one.
#
# The envelope's own `code`, `message` and `errors` survive onto the error, and
# none of the diagnostics contain the API key.
#
# Run:  PACTMAN_API_KEY=... bundle exec ruby examples/ex_16_not_found.rb

require_relative "lib/fixture_api"
require_relative "lib/print"

NCP = Pactman::NonprofitCheckPlus
include Print

FixtureApi.with_fixture_api do |client|
  no_record = FixtureApi::EINS[:no_record]

  heading "Single check for #{no_record} — well formed, no record"

  begin
    result = client.nonprofits.check(no_record)
    puts "  Unexpectedly succeeded: #{result.nonprofit&.organization_name}"
  rescue NCP::NotFoundError => e
    # Stable identity: class, category, and origin. Never parse `message`.
    field "class", e.class.name
    field "category", e.category.inspect
    field "origin", e.origin.inspect
    field "is an ApiError", e.is_a?(NCP::ApiError)
    field "is an NCP::Error", e.is_a?(NCP::Error)
    field "matches the not_found category", e.category == NCP::ErrorCategory::NOT_FOUND

    heading "  Response detail carried on the error"
    field "status", e.status
    field "api_code (envelope code)", e.api_code
    field "api_message", e.api_message
    field "request_id", e.request_id
    field "attempts", e.attempts
    field "retry_after_seconds", e.retry_after_seconds

    e.api_errors.each do |detail|
      bullet "resource=#{detail.resource} code=#{detail.code || "-"} reason=#{detail.reason}"
    end

    # Sanitized diagnostics: safe to log, safe to attach to a support ticket.
    heading "  error.to_h — what you can safely log"
    json_block e.to_h

    serialized = e.to_json + e.full_message
    field "contains the API key", serialized.include?(ENV.fetch("PACTMAN_API_KEY"))

    # 404 is never retried, whatever the retry policy says.
    field "attempts made", "#{e.attempts} — not-found is not a transient failure"
  end

  # The bulk endpoint behaves differently, and this is the part that surprises
  # people: unmatched EINs come back on a successful 200 as item-level errors.
  # Only a request where *nothing* matched is a 404.
  heading "Bulk — mixed input returns HTTP 200, not an error"

  mixed = client.nonprofits.check_bulk([FixtureApi::EINS[:public_charity], no_record])

  field "status", mixed.status
  field "organizations returned", mixed.organizations.size
  field "not_found_eins", mixed.not_found_eins.join(", ")

  heading "Bulk — nothing matched at all"

  begin
    client.nonprofits.check_bulk([no_record])
    puts "  Unexpectedly succeeded."
  rescue NCP::ApiError => e
    field "class", e.class.name
    field "status", e.status
    field "api_message", e.api_message
  end
end

note "Distinguish \"we could not find it\" from \"we could not ask\". A 404 means the\n" \
     "record is absent; a timeout or a 503 means you learned nothing. Only the first\n" \
     "is a fact about the organization."
