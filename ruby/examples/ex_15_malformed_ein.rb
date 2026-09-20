# frozen_string_literal: true

# EX-15 — Malformed EIN rejected locally.
#
# Bad input never becomes a request. Every rejection below happens in-process, so
# it costs no quota, no latency, and no rate-limit budget.
#
# The example counts outbound HTTP calls with an instrumented adapter to prove the
# claim rather than assert it.
#
# Run:  PACTMAN_API_KEY=... bundle exec ruby examples/ex_15_malformed_ein.rb

require_relative "lib/client"
require_relative "lib/print"

NCP = Pactman::NonprofitCheckPlus
include Print

# A counting wrapper around the default adapter. If any call below reaches the
# network, this number moves.
class CountingAdapter
  attr_reader :requests_sent

  def initialize
    @inner = NCP::Http::NetHttpAdapter.new
    @requests_sent = 0
  end

  def call(request)
    @requests_sent += 1
    @inner.call(request)
  end
end

adapter = CountingAdapter.new
client = NCP::Client.new(api_key: ExampleClient.require_api_key, base_url: ENV.fetch("PACTMAN_BASE_URL", nil),
                         http_adapter: adapter)

BAD_SINGLE_INPUTS = [
  ["too few digits", "41178709"],
  ["too many digits", "4117870977"],
  ["letters", "41-178709A"],
  ["empty string", ""],
  ["whitespace only", "   "],
  ["nil", nil],
  ["an Integer, not a String", 411_787_097],
  ["unsupported punctuation", "41.1787097"],
  ["hyphen in the wrong place", "411-787097"],
  ["two hyphens", "41-178-7097"]
].freeze

heading "Single checks (EINs are #{NCP::EIN::LENGTH} digits, optionally hyphenated XX-XXXXXXX)"

BAD_SINGLE_INPUTS.each do |label, value|
  client.nonprofits.check(value)
  puts "  #{label.ljust(26)} UNEXPECTEDLY ACCEPTED"
rescue NCP::ValidationError => e
  # `issues` identifies the offending value, so a form can highlight the field
  # rather than showing a generic failure.
  issue = e.issues.first

  puts "  #{label.ljust(26)} valid?=#{NCP::EIN.valid?(value).to_s.ljust(6)} origin=#{e.origin}  " \
       "#{issue&.message || e.message}"
end

heading "Bulk checks — every failure is reported at once, by index"

[
  ["one bad entry", %w[411787097 nope 996589560]],
  ["several bad entries", ["1234", "411787097", "", nil]],
  ["not an Array", "not-an-array"],
  ["empty Array", []]
].each do |label, batch|
  client.nonprofits.check_bulk(batch)
  puts "  #{label}: UNEXPECTEDLY ACCEPTED"
rescue NCP::ValidationError => e
  puts "\n  #{label}: #{e.message}"
  e.issues.each { |issue| bullet "index #{issue.index}: #{issue.value.inspect} — #{issue.message}" }
end

# One valid call, to show the counter is wired up and does move.
if ENV["PACTMAN_BASE_URL"]
  begin
    client.nonprofits.check("411787097")
  rescue NCP::Error
    nil
  end
end

heading "Network activity"
field "HTTP requests sent", adapter.requests_sent
field "expected", ENV["PACTMAN_BASE_URL"] ? "1 (the single valid call at the end)" : "0"

note "Validation is about shape only. `EIN.valid?` returning true means the value\n" \
     "looks like an EIN — not that the organization exists, is exempt, or is the one\n" \
     "your applicant claims to be."
