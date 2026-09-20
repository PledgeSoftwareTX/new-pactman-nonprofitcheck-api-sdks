# frozen_string_literal: true

# Bulk nonprofit check with local validation and result iteration.
#
# Run:  PACTMAN_API_KEY=... bundle exec ruby examples/bulk.rb

require "pactman/nonprofit_check_plus"

NCP = Pactman::NonprofitCheckPlus

api_key = ENV.fetch("PACTMAN_API_KEY", "")

if api_key.empty?
  warn "Set PACTMAN_API_KEY before running this example."
  exit 1
end

client = NCP::Client.new(api_key: api_key, base_url: ENV.fetch("PACTMAN_BASE_URL", nil))

eins = %w[41-1787097 996589560]

puts "Checking #{eins.size} EINs (server limit is #{NCP::MAX_BULK_EINS} per request)."

begin
  result = client.nonprofits.check_bulk(eins)

  puts "\nMatched #{result.organizations.size} organizations."

  result.organizations.each do |org|
    pub78 = NCP::Sources.pub78(org)
    puts "  #{org.ein}  #{org.organization_name}  pub78_listed=#{pub78.nil? ? "n/a" : pub78.verified.inspect}"
  end

  # EINs with no record come back on a successful response, not as an error.
  puts "\nNo record for: #{result.not_found_eins.join(", ")}" unless result.not_found_eins.empty?

  puts "\nChecks consumed: #{result.check_count}"
rescue NCP::ValidationError => e
  # Nothing was sent — the whole batch is rejected before the request.
  warn "Local validation failed, no request was sent:"
  e.issues.each { |issue| warn "  index #{issue.index}: #{issue.message}" }
  exit 1
end

# Duplicates are sent as supplied, because each one consumes quota. Pass
# `dedupe: true` to collapse them first.
