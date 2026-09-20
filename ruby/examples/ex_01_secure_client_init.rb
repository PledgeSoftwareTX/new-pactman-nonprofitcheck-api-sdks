# frozen_string_literal: true

# EX-01 — Secure client initialization.
#
# Loads the API key from an environment variable, selects the environment,
# configures a finite timeout, and builds one reusable client. Then it proves the
# key does not leak into logs, debug output, serializers, or exceptions.
#
# Run:  PACTMAN_API_KEY=... bundle exec ruby examples/ex_01_secure_client_init.rb

require "pactman/nonprofit_check_plus"
require "pp"
require "stringio"
require "yaml"
require_relative "lib/print"

NCP = Pactman::NonprofitCheckPlus
include Print

# 1. The key comes from the environment. It is never a literal in source, never
#    committed, and never shipped anywhere an end user can read it.
api_key = ENV.fetch("PACTMAN_API_KEY", "")

if api_key.empty?
  warn "Set PACTMAN_API_KEY before running this example."
  warn "Load it from your secret manager or a .env file excluded from git."
  exit 1
end

# 2. One client, built once, reused for the life of the process. It is safe to
#    share across threads, and it carries the throttle state for all of them.
client = NCP::Client.new(
  api_key: api_key,

  # Production is the default; naming it makes the intent explicit at review time.
  environment: NCP::Environment::PRODUCTION,

  # 3. A finite timeout, in seconds. The default is 30 and there is no way to
  #    disable it, but a caller-facing service usually wants something shorter.
  timeout: 10,

  # A mock or a host Pactman gave you directly overrides `environment`.
  base_url: ENV.fetch("PACTMAN_BASE_URL", nil)
)

heading "Resolved configuration"
field "base_url", client.base_url
field "environment", client.environment.inspect
field "timeout (s)", client.timeout
field "SDK default timeout (s)", NCP::DEFAULT_TIMEOUT

# 4. Every diagnostic surface is checked against the real key. None of them
#    contain it — the key lives in a closure inside the transport, not in any
#    instance variable, and the error types never copy it into a message.
caught = begin
  NCP::Client.new(api_key: api_key, base_url: "not-a-url")
  nil
rescue NCP::ConfigurationError => e
  e
end

pretty = StringIO.new
PP.pp(client, pretty)

surfaces = {
  "p client (inspect)" => client.inspect,
  "pp client" => pretty.string,
  "client.to_json" => client.to_json,
  "client.to_s" => client.to_s,
  "client.to_yaml" => client.to_yaml,
  "error.message" => caught&.message || "",
  "error.to_json" => caught.to_json,
  "error.full_message" => caught&.full_message || ""
}

heading "Credential redaction"

surfaces.each do |surface, text|
  field surface, text.include?(api_key) ? "LEAKED THE KEY" : "clean"
end

leaked = surfaces.values.any? { |text| text.include?(api_key) }

heading "Client as printed"
pp client

puts
field "configuration error type", caught.is_a?(NCP::ConfigurationError)

note "The key is sent only as an Authorization header at request time. Rotate it if\n" \
     "it is ever printed, logged, or committed."

exit 1 if leaked
