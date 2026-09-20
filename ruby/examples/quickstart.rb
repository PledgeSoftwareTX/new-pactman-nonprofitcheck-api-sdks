# frozen_string_literal: true

# Minimal single nonprofit check.
#
# Run:  PACTMAN_API_KEY=... bundle exec ruby examples/quickstart.rb [EIN]
#
# The key is read from the environment. Never hard-code it — the key is a private
# server-side credential.

require "pactman/nonprofit_check_plus"

api_key = ENV.fetch("PACTMAN_API_KEY", "")

if api_key.empty?
  warn "Set PACTMAN_API_KEY before running this example."
  exit 1
end

client = Pactman::NonprofitCheckPlus::Client.new(
  api_key: api_key,
  # Production is the default. PACTMAN_BASE_URL is only for a local mock server.
  base_url: ENV.fetch("PACTMAN_BASE_URL", nil),
  timeout: 15
)

ein = ARGV.fetch(0, "41-1787097")
result = client.nonprofits.check(ein)
nonprofit = result.nonprofit

if nonprofit.nil?
  puts "No record for EIN #{ein}."
  exit 0
end

puts "Organization : #{nonprofit.organization_name}"
puts "EIN          : #{nonprofit.ein}"
puts "Location     : #{nonprofit.city}, #{nonprofit.state}"
puts "Profile      : #{nonprofit.pactman_org_url}"
puts "Checks used  : #{result.check_count}"

# Source-specific findings, read straight from the API response.
pub78 = Pactman::NonprofitCheckPlus::Sources.pub78(nonprofit)
bmf = Pactman::NonprofitCheckPlus::Sources.bmf(nonprofit)
ofac = Pactman::NonprofitCheckPlus::Sources.ofac(nonprofit)

puts "\nIRS Publication 78"
puts pub78.nil? ? "  not returned" : "  listed: #{pub78.verified}, as of #{pub78.most_recent}"

puts "\nIRS Business Master File"
puts bmf.nil? ? "  not returned" : "  status: #{bmf.status}, subsection: #{bmf.subsection_description}"

puts "\nOFAC"
puts ofac.nil? ? "  not returned" : "  #{ofac.status}"

# A syntactically valid EIN and a clean set of findings are not an eligibility
# decision. Apply your own grantmaking, compliance and risk policy.
