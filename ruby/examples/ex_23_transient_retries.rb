# frozen_string_literal: true

# EX-23 — Transient network or server failure.
#
# Retries are on by default: two of them, exponential backoff from 0.5 seconds
# with full jitter, capped at 8 seconds per delay. Eligible are 429, 500, 502,
# 503, 504 and connection failures that produced no response.
#
# Never retried, whatever `retryable_statuses` contains: 400, 401, 403, 404, and
# anything rejected by local validation. Retrying a rejected API key just burns
# the same key three times; retrying a 404 cannot make a record exist.
#
# Run:  PACTMAN_API_KEY=... bundle exec ruby examples/ex_23_transient_retries.rb

require_relative "lib/fixture_api"
require_relative "lib/print"

NCP = Pactman::NonprofitCheckPlus
include Print

def monotonic_ms
  (Process.clock_gettime(Process::CLOCK_MONOTONIC) * 1000).round
end

FixtureApi.with_fixture_api do |client, base_url|
  transient = FixtureApi::CONTROL_EINS[:transient_failure]

  # The fixture endpoint answers 503 twice, then succeeds — a textbook transient
  # failure. Delays are shortened here so the example runs quickly; the defaults
  # are 0.5 seconds initial and 8 seconds maximum.
  heading "A 503 that clears on retry"

  started_at = monotonic_ms
  result = client.nonprofits.check(transient, retry: { max_retries: 3, initial_delay: 0.04, max_delay: 0.4 })

  field "status", result.status
  field "organization", result.nonprofit&.organization_name
  field "elapsed (ms)", monotonic_ms - started_at
  bullet "Two 503s were absorbed; the caller saw one successful result."
  bullet "Backoff grows exponentially and is jittered, so parallel clients scatter."

  heading "The same failure with retries disabled"

  begin
    client.nonprofits.check(transient, retry: false)
    puts "  Unexpectedly succeeded."
  rescue NCP::ServerError => e
    field "class", e.class.name
    field "status", e.status
    field "attempts", e.attempts
    field "api_message", e.api_message
  end

  heading "Failures that are never retried"

  # 404 — a definite answer. Retrying cannot change it.
  begin
    client.nonprofits.check(FixtureApi::EINS[:no_record], retry: { max_retries: 5, retryable_statuses: [404, 500] })
  rescue NCP::NotFoundError => e
    field "404 attempts", "#{e.attempts} — not retried even though 404 was listed"
  end

  # 401 — retrying a rejected credential achieves nothing.
  bad_key_client = NCP::Client.new(api_key: "obviously-not-a-real-key", base_url: base_url, retry: { max_retries: 3 })

  begin
    bad_key_client.nonprofits.check(FixtureApi::EINS[:public_charity])
  rescue NCP::AuthenticationError => e
    field "401 attempts", "#{e.attempts} — authentication failures are terminal"
  end

  # Local validation — nothing was sent, so there is nothing to retry.
  begin
    client.nonprofits.check("not-an-ein", retry: { max_retries: 3 })
  rescue NCP::ValidationError => e
    field "validation", "origin=#{e.origin} — rejected before any request"
  end

  # A connection that never reaches a server: retried, then surfaced as a network
  # error carrying the attempt count and the underlying exception as its cause.
  heading "A connection failure"

  unreachable = NCP::Client.new(api_key: ENV.fetch("PACTMAN_API_KEY"), base_url: "http://127.0.0.1:1", timeout: 2,
                                retry: { max_retries: 2, initial_delay: 0.02, max_delay: 0.06 })

  begin
    unreachable.nonprofits.check(FixtureApi::EINS[:public_charity])
  rescue NCP::NetworkError => e
    field "class", e.class.name
    field "category", e.category.inspect
    field "attempts", e.attempts
    field "cause", e.cause.class.name
    field "message", e.message
  end
end

note "A retried failure that eventually succeeds is a success. A retried failure that\n" \
     "exhausts its budget is an outage — record it as \"not checked\", never as a pass."
