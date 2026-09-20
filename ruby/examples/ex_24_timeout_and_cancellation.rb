# frozen_string_literal: true

# EX-24 — Timeout and request cancellation.
#
# The timeout is always finite — 30 seconds by default, configurable per client
# or per request, and impossible to disable. Cancellation is Ruby's own: kill the
# thread doing the work, or bound it with `Timeout.timeout`. Under a fiber
# scheduler, stopping the task does the same.
#
# The two are different events and stay different types:
#
#   Pactman::NonprofitCheckPlus::TimeoutError   the deadline you configured expired
#   Timeout::Error, or nothing at all            you cancelled; the SDK is not involved
#
# The SDK never converts a cancellation into one of its own errors, and never
# retries through one. Conflating them hides which side gave up: a timeout
# usually means raise the budget or shed load; a cancellation means the caller
# went away.
#
# Run:  PACTMAN_API_KEY=... bundle exec ruby examples/ex_24_timeout_and_cancellation.rb

require "timeout"
require_relative "lib/fixture_api"
require_relative "lib/print"

NCP = Pactman::NonprofitCheckPlus
include Print

def monotonic_ms
  (Process.clock_gettime(Process::CLOCK_MONOTONIC) * 1000).round
end

# One handler, every outcome, no string matching.
def classify(error)
  case error
  when NCP::TimeoutError then "timeout after #{error.timeout}s — raise the budget or shed load"
  when Timeout::Error then "cancelled by the caller's own deadline — the API was never at fault"
  when NCP::NetworkError then "unreachable — nothing answered"
  else "something else entirely"
  end
end

FixtureApi.with_fixture_api do |client|
  slow = FixtureApi::CONTROL_EINS[:slow]

  # The fixture endpoint holds the response open, so a short deadline expires.
  heading "A per-request timeout"

  started_at = monotonic_ms

  begin
    client.nonprofits.check(slow, timeout: 0.25, retry: false)
    puts "  Unexpectedly succeeded."
  rescue NCP::TimeoutError => e
    field "class", e.class.name
    field "category", e.category.inspect
    field "origin", e.origin.inspect
    field "timeout (s)", e.timeout
    field "attempts", e.attempts
    field "elapsed (ms)", monotonic_ms - started_at
    field "is a Timeout::Error", e.is_a?(Timeout::Error)
  end

  # Cancellation by killing the thread. The in-flight request is abandoned, its
  # socket is closed on the way out, and no retry the SDK had planned will run.
  heading "Caller cancellation with Thread#kill"

  cancel_started_at = monotonic_ms
  worker = Thread.new { client.nonprofits.check(slow, timeout: 10) }

  sleep 0.2
  worker.kill
  worker.join

  field "worker alive", worker.alive?
  field "worker status", worker.status.inspect
  field "elapsed (ms)", monotonic_ms - cancel_started_at

  # Cancellation by a caller-side deadline around the whole operation, retries
  # included. What comes out is Ruby's Timeout::Error, not the SDK's.
  heading "Bounding an operation with Timeout.timeout"

  begin
    Timeout.timeout(0.2) { client.nonprofits.check(slow, timeout: 10, retry: { max_retries: 3 }) }
    puts "  Unexpectedly succeeded."
  rescue Timeout::Error => e
    field "class", e.class.name
    field "is an SDK error", e.is_a?(NCP::Error)
  end

  heading "Distinguishing them in one handler"

  {
    "deadline" => -> { client.nonprofits.check(slow, timeout: 0.15, retry: false) },
    "caller" => -> { Timeout.timeout(0.15) { client.nonprofits.check(slow, timeout: 10) } }
  }.each do |label, run|
    run.call
    puts "  #{label}: unexpectedly succeeded"
  rescue StandardError => e
    field label, classify(e)
  end

  bullet "Killing a thread before its call starts means no request is made at all."
  bullet "Killing it mid-flight abandons the attempt and any retries still planned."
  bullet "Rescue StandardError, not Exception, and a cancellation passes straight through."
end

note "There is no way to disable the timeout, by design. An unbounded request holds a\n" \
     "connection, a thread, and a caller's patience for as long as the network lets it."
