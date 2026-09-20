# frozen_string_literal: true

# Access to the bundled fixture API.
#
# Some scenarios cannot be summoned on demand from the production API: a revoked
# exemption, an OFAC match, a cross-source conflict, an HTTP 429, a response
# carrying a field newer than this SDK. Examples that need one of those run
# against the fixture server in `scripts/mock_server.rb`, which speaks the same
# envelope, error and check-count semantics as the real service.
#
# Set `PACTMAN_BASE_URL` to point these examples somewhere else instead.

require_relative "client"
require_relative "../../scripts/mock_server"

module FixtureApi
  EINS = Fixtures::EINS
  CONTROL_EINS = Fixtures::CONTROL_EINS

  module_function

  # Every field this SDK version declares on an organization.
  def known_nonprofit_fields
    Fixtures.known_nonprofit_fields
  end

  # Runs the block with a client pointed at the fixture API.
  #
  # The server is started only when `PACTMAN_BASE_URL` is unset, and is always
  # closed afterwards, so the example leaves no background work behind.
  #
  # @yieldparam client [Pactman::NonprofitCheckPlus::Client]
  # @yieldparam base_url [String]
  def with_fixture_api(**overrides)
    api_key = ExampleClient.require_api_key
    external = ENV.fetch("PACTMAN_BASE_URL", nil)
    fixture = external ? nil : MockServer.start(api_key: api_key)
    base_url = external || fixture.url

    unless external
      puts "Using the bundled fixture API at #{base_url} — these scenarios need"
      puts "records and responses a live API will not produce on request."
    end

    client = Pactman::NonprofitCheckPlus::Client.new(api_key: api_key, base_url: base_url, timeout: 15, **overrides)

    yield client, base_url
  ensure
    fixture&.close
  end
end
