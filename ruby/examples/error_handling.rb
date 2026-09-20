# frozen_string_literal: true

# Branching on error type: local validation, authentication, and rate limits.
#
# Run:  PACTMAN_API_KEY=... bundle exec ruby examples/error_handling.rb

require "pactman/nonprofit_check_plus"

NCP = Pactman::NonprofitCheckPlus

api_key = ENV.fetch("PACTMAN_API_KEY", "")

if api_key.empty?
  warn "Set PACTMAN_API_KEY before running this example."
  exit 1
end

client = NCP::Client.new(api_key: api_key, base_url: ENV.fetch("PACTMAN_BASE_URL", nil), timeout: 10,
                         retry: { max_retries: 2 })

# One place to turn any SDK failure into an action. No string parsing.
def explain(error)
  case error
  when NCP::ValidationError
    detail = error.issues.empty? ? error.message : error.issues.map(&:message).join(" ")
    "Local validation — fix the input. #{detail}"
  when NCP::AuthenticationError
    "Authentication — the API key was rejected. Check PACTMAN_API_KEY."
  when NCP::RateLimitError
    "Rate limited — retry after #{error.retry_after_seconds || "an unspecified number of"} seconds."
  when NCP::TimeoutError
    "Timed out after #{error.timeout}s — raise the timeout or retry later."
  when NCP::NetworkError
    "Network failure — the request never reached the API."
  when NCP::ApiError
    "API error #{error.status} (request #{error.request_id || "unknown"}): #{error.message}"
  else
    "Unexpected: #{error}"
  end
end

# 1. A malformed EIN never leaves the process.
begin
  client.nonprofits.check("41178709")
rescue NCP::Error => e
  puts "malformed EIN -> #{explain(e)}"
end

# 2. An empty batch is rejected locally too.
begin
  client.nonprofits.check_bulk([])
rescue NCP::Error => e
  puts "empty batch   -> #{explain(e)}"
end

# 3. A bad key produces an authentication error on first use.
begin
  bad_client = NCP::Client.new(api_key: "obviously-not-a-real-key", base_url: ENV.fetch("PACTMAN_BASE_URL", nil),
                               retry: false)

  bad_client.nonprofits.check("411787097")
  puts "bad key       -> unexpectedly succeeded"
rescue NCP::Error => e
  puts "bad key       -> #{explain(e)}"
end

# 4. A real call, handled the same way.
begin
  result = client.nonprofits.check("41-1787097")
  puts "valid check   -> #{result.nonprofit&.organization_name || "no record"}"
rescue NCP::Error => e
  puts "valid check   -> #{explain(e)}"
end
