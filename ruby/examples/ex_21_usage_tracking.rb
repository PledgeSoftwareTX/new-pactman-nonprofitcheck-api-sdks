# frozen_string_literal: true

# EX-21 — Billing-cycle usage tracking.
#
# `nonprofit_check_count`, surfaced as `result.check_count`, is the running total
# of checks your account has consumed so far in the current billing cycle. It is
# never the size of the request you just made.
#
# The test is one thing: fetch one nonprofit by EIN, and confirm the API sent that
# counter as a JSON number. The SDK maps anything else to `nil`, which downstream
# is indistinguishable from "not reported", so the check reads the uncoerced value
# off `raw`. This example exits non-zero when it is not a number.
#
# Run:  PACTMAN_API_KEY=... bundle exec ruby examples/ex_21_usage_tracking.rb [EIN]

require_relative "lib/client"
require_relative "lib/fixture_api"
require_relative "lib/print"

include Print

# The JSON type of a value, in the vocabulary the response contract uses.
def json_type_of(value)
  case value
  when nil then "null"
  when Array then "array"
  when Hash then "object"
  when String then "string"
  when true, false then "boolean"
  when Numeric then "number"
  else value.class.name
  end
end

client = ExampleClient.create_client
ein = ARGV.fetch(0, FixtureApi::EINS[:public_charity])

result = client.nonprofits.check(ein)

# `check_count` is `Numeric` or `nil`, and the SDK produces that `nil` both for a
# counter the API sent as null and for one it sent as `"42"`. Only `raw`, which
# nothing has coerced, tells them apart.
envelope = result.raw
sent = envelope.is_a?(Hash) && envelope.key?("nonprofit_check_count")
wire_value = sent ? envelope["nonprofit_check_count"] : nil
wire_type = sent ? json_type_of(wire_value) : "<not returned>"

heading "nonprofit_check_count on the wire"
field "ein", ein
field "wire type", wire_type
field "check_count", result.check_count

note "The counter is cumulative for the billing cycle and resets when a new one starts.\n" \
     "A bulk call for five EINs does not return 5 — it returns your cycle total."

if wire_type != "number"
  warn "\nnonprofit_check_count arrived as #{wire_type}#{" #{JSON.generate(wire_value)}" if sent}, " \
       "not a number, so check_count reads nil."
  exit 1
end
