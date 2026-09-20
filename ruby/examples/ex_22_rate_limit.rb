# frozen_string_literal: true

# EX-22 — Rate-limit response and Retry-After.
#
# HTTP 429 becomes `RateLimitError`, carrying the status, the server's
# `Retry-After` when it sent one, and sanitized request metadata.
#
# Three behaviours are shown: surfacing the error with retries off, letting the
# bounded retry policy honour `Retry-After`, and reducing pressure with a
# client-side ceiling plus a bounded pool of worker threads.
#
# Run:  PACTMAN_API_KEY=... bundle exec ruby examples/ex_22_rate_limit.rb

require "time"
require_relative "lib/client"
require_relative "lib/fixture_api"
require_relative "lib/print"

NCP = Pactman::NonprofitCheckPlus
include Print

# Runs the block over `items` with at most `limit` threads in flight, keeping
# results in input order. The SDK does not queue for you.
def with_concurrency(items, limit)
  queue = Queue.new
  items.each_with_index { |item, index| queue << [item, index] }
  queue.close

  results = Array.new(items.size)

  Array.new([limit, items.size].min) do
    Thread.new do
      while (next_item = queue.pop)
        item, index = next_item
        results[index] = yield(item)
      end
    end
  end.each(&:join)

  results
end

def monotonic_ms
  (Process.clock_gettime(Process::CLOCK_MONOTONIC) * 1000).round
end

FixtureApi.with_fixture_api do |client, base_url|
  rate_limited = FixtureApi::CONTROL_EINS[:rate_limited]

  # 1. Retries off, so the 429 reaches the caller untouched.
  heading "Surfacing the error"

  begin
    client.nonprofits.check(rate_limited, retry: false)
    puts "  Unexpectedly succeeded."
  rescue NCP::RateLimitError => e
    field "class", e.class.name
    field "category", e.category.inspect
    field "status", e.status
    field "retry_after_seconds", e.retry_after_seconds
    field "request_id", e.request_id
    field "attempts", e.attempts
    field "api_message", e.api_message

    e.api_errors.each { |detail| bullet "#{detail.resource}: #{detail.reason}" }

    # Safe to log wholesale — no credential reaches any of these fields.
    field "to_json contains the key", e.to_json.include?(ENV.fetch("PACTMAN_API_KEY"))

    # Schedule your own backoff from the server's number when you handle 429s
    # yourself. Fall back to your own delay when it is absent.
    field "would retry at", (Time.now + (e.retry_after_seconds || 5)).utc.iso8601
  end

  # 2. Bounded automatic retry. 429 is retryable and `Retry-After` wins over
  #    computed backoff, so the SDK waits exactly as long as it was told to.
  heading "Bounded automatic retry"

  started_at = monotonic_ms

  begin
    client.nonprofits.check(rate_limited, retry: { max_retries: 1, respect_retry_after: true })
    puts "  Unexpectedly succeeded."
  rescue NCP::RateLimitError => e
    field "class", e.class.name
    field "attempts", e.attempts
    field "elapsed (ms)", monotonic_ms - started_at
    bullet "The retry honoured Retry-After, then gave up at the configured bound."
    bullet "Retries stay finite; the SDK never retries indefinitely."
  end

  # 3. Reduce pressure rather than absorb rejections: cap outbound rate and keep
  #    your own concurrency small. Prefer one bulk call to many single ones.
  heading "Reducing pressure"

  paced = NCP::Client.new(api_key: ExampleClient.require_api_key, base_url: base_url, max_requests_per_second: 3,
                          retry: { max_retries: 2 })

  eins = FixtureApi::EINS.values_at(:public_charity, :public_charity_second, :private_foundation, :reinstated)
  begin_at = monotonic_ms

  # One client, shared by every thread: the throttle is per client, so it is
  # only a ceiling if everyone goes through the same one.
  names = with_concurrency(eins, 2) do |ein|
    paced.nonprofits.check(ein).nonprofit&.organization_name || "no record"
  end

  field "max_requests_per_second", 3
  field "concurrency limit", 2
  field "requests", names.size
  field "elapsed (ms)", monotonic_ms - begin_at

  names.each { |name| bullet name }
end

note "The server's limits are authoritative and can change per account and endpoint.\n" \
     "Treat max_requests_per_second as a courtesy throttle, not a guarantee, and prefer\n" \
     "the bulk endpoint over a fan-out of single checks."
