# frozen_string_literal: true

# EX-03 — Basic nonprofit identity lookup.
#
# Retrieves an organization and reads its identity fields. The model and the
# untouched response body are both available; neither replaces the other.
#
# Run:  PACTMAN_API_KEY=... bundle exec ruby examples/ex_03_identity_lookup.rb [EIN]

require_relative "lib/client"
require_relative "lib/fixture_api"
require_relative "lib/print"

include Print

client = ExampleClient.create_client
ein = ARGV.fetch(0, FixtureApi::EINS[:public_charity])

result = client.nonprofits.check(ein)
nonprofit = result.nonprofit

if nonprofit.nil?
  puts "No record for EIN #{ein}."
  exit 0
end

heading "Identity"
field "ein", nonprofit.ein
field "organization_name", nonprofit.organization_name
field "organization_name_aka", returned(nonprofit, :organization_name_aka)
field "pactman_org_url", nonprofit.pactman_org_url

# `organization_name_aka` is frequently null. That is "the API has no alternate
# name on file", not "the organization has no alternate name".

heading "Response metadata"
field "status", result.status
field "request_id", result.request_id
field "time_taken_ms", result.time_taken_ms
field "check_count", result.check_count

# The model is a view over the envelope, not a replacement for it. `raw` is
# exactly what the server sent, including anything not declared on the model.
heading "Raw envelope"
field 'raw["code"]', result.raw["code"]
field 'raw["message"]', result.raw["message"]
field 'raw["data"]["ein"]', result.raw.dig("data", "ein")
field "fields returned", nonprofit.keys.size

note "A returned profile URL means Pactman holds a page for the organization. It is\n" \
     "not an endorsement, and not a statement about tax-exempt status."
