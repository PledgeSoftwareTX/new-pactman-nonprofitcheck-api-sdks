# frozen_string_literal: true

require_relative "test_helper"
require "pp"
require "stringio"
require "yaml"

class ClientConstructionTest < Minitest::Test
  include TestSupport

  def test_creates_a_client_from_the_minimum_documented_configuration
    client = NCP::Client.new(api_key: TEST_API_KEY)

    assert_equal NCP.base_url_for_environment(NCP::Environment::PRODUCTION), client.base_url
    assert_equal NCP::DEFAULT_ENVIRONMENT, client.environment
    assert_equal 30, client.timeout
  end

  def test_rejects_unusable_api_keys_locally
    { "missing" => nil, "empty" => "", "whitespace-only" => "   ", "a number" => 42 }.each do |label, api_key|
      error = assert_raises(NCP::ConfigurationError, label) { NCP::Client.new(api_key: api_key) }

      assert_equal :configuration, error.category
      assert_equal :local, error.origin
    end

    assert_raises(NCP::ConfigurationError) { NCP::Client.new }
  end

  def test_sends_no_request_when_the_api_key_is_empty
    adapter = FakeAdapter.new([{ body: envelope(nonprofit_fixture) }])

    assert_raises(NCP::ConfigurationError) { NCP::Client.new(api_key: "", http_adapter: adapter) }
    assert_empty adapter.requests
  end

  def test_names_an_option_the_client_does_not_have
    error = assert_raises(ArgumentError) { NCP::Client.new(api_key: TEST_API_KEY, timeout_ms: 1_500) }

    assert_includes error.message, "timeout_ms"
    assert_includes error.message, "seconds"
  end
end

class EnvironmentSelectionTest < Minitest::Test
  include TestSupport

  def test_resolves_a_url_for_every_named_environment
    environments = NCP.supported_environments

    assert_includes environments, NCP::Environment::PRODUCTION

    environments.each do |environment|
      client = NCP::Client.new(api_key: TEST_API_KEY, environment: environment)

      assert_match %r{\Ahttps://}, client.base_url
      URI.parse(client.base_url)
    end
  end

  def test_accepts_the_environment_as_a_string
    assert_equal :production, NCP::Client.new(api_key: TEST_API_KEY, environment: "production").environment
  end

  def test_exposes_production_only
    assert_equal [NCP::Environment::PRODUCTION], NCP.supported_environments

    NCP.supported_environments.each do |environment|
      refute_match(/sandbox|sit|qa|hllc\.mobi/i, NCP.base_url_for_environment(environment))
    end
  end

  def test_accepts_a_custom_base_url_for_a_local_mock_server
    client = NCP::Client.new(api_key: TEST_API_KEY, base_url: "http://127.0.0.1:4010")

    assert_equal "http://127.0.0.1:4010", client.base_url
    assert_nil client.environment
  end

  def test_normalizes_a_custom_base_url
    assert_equal "https://example.test", NCP::Client.new(api_key: TEST_API_KEY, base_url: "https://example.test/").base_url
    assert_equal "https://example.test/proxy",
                 NCP::Client.new(api_key: TEST_API_KEY, base_url: " HTTPS://Example.TEST:443/proxy// ").base_url
  end

  def test_treats_a_nil_base_url_as_not_given
    assert_equal :production, NCP::Client.new(api_key: TEST_API_KEY, base_url: nil).environment
  end

  def test_rejects_unusable_base_urls_locally
    { "not a url" => "entities.pactman.org", "empty" => "", "an unsupported scheme" => "ftp://entities.pactman.org",
      "spaces" => "not a url", "a number" => 42 }.each do |label, base_url|
      assert_raises(NCP::ConfigurationError, label) { NCP::Client.new(api_key: TEST_API_KEY, base_url: base_url) }
    end
  end

  def test_rejects_an_unknown_environment_name
    assert_raises(NCP::ConfigurationError) { NCP::Client.new(api_key: TEST_API_KEY, environment: :staging) }
    assert_raises(ArgumentError) { NCP.base_url_for_environment(:staging) }
  end
end

class OptionValidationTest < Minitest::Test
  include TestSupport

  INVALID = {
    "a zero timeout" => { timeout: 0 },
    "a negative timeout" => { timeout: -1 },
    "an infinite timeout" => { timeout: Float::INFINITY },
    "a string timeout" => { timeout: "30" },
    "a negative retry count" => { retry: { max_retries: -1 } },
    "a fractional retry count" => { retry: { max_retries: 1.5 } },
    "a backoff factor below 1" => { retry: { backoff_factor: 0.5 } },
    "an unknown retry option" => { retry: { max_attempts: 3 } },
    "a non-boolean jitter" => { retry: { jitter: "yes" } },
    "a retry that is not a policy" => { retry: 3 },
    "a zero request-per-second cap" => { max_requests_per_second: 0 },
    "headers that are not a Hash" => { default_headers: "X-Team: grants" },
    "a header value with a line break" => { default_headers: { "X-Team" => "grants\r\nX-Evil: 1" } },
    "an adapter that cannot be called" => { http_adapter: Object.new }
  }.freeze

  def test_rejects_nonsensical_options
    INVALID.each do |label, overrides|
      assert_raises(NCP::ConfigurationError, label) { NCP::Client.new(api_key: TEST_API_KEY, **overrides) }
    end
  end

  def test_honours_an_explicit_timeout
    assert_in_delta 1.5, NCP::Client.new(api_key: TEST_API_KEY, timeout: 1.5).timeout
  end

  def test_merges_a_retry_hash_onto_the_defaults
    policy = NCP::Client.new(api_key: TEST_API_KEY, retry: { max_retries: 5 }).retry_policy

    assert_equal 5, policy.max_retries
    assert_in_delta 0.5, policy.initial_delay
  end

  def test_disables_retrying_with_false
    assert_equal 0, NCP::Client.new(api_key: TEST_API_KEY, retry: false).retry_policy.max_retries
  end

  def test_freezes_a_copy_of_the_retryable_statuses
    statuses = [500]
    policy = NCP::RetryPolicy.new(retryable_statuses: statuses)

    statuses << 404

    assert_equal [500], policy.retryable_statuses
    assert_predicate policy.retryable_statuses, :frozen?
  end
end

class CredentialRedactionTest < Minitest::Test
  include TestSupport

  def setup
    @client = NCP::Client.new(api_key: TEST_API_KEY)
  end

  def test_keeps_the_key_out_of_json_and_to_h
    assert_equal "[redacted]", JSON.parse(@client.to_json)["api_key"]
    refute_includes @client.to_json, TEST_API_KEY
    refute_includes @client.to_h.to_s, TEST_API_KEY
  end

  def test_keeps_the_key_out_of_inspect_pp_and_to_s
    printed = StringIO.new
    PP.pp(@client, printed)

    [@client.inspect, printed.string, @client.to_s, @client.nonprofits.inspect].each do |surface|
      refute_includes surface, TEST_API_KEY
    end
  end

  def test_writes_the_redacted_view_to_yaml_without_walking_into_the_adapter
    adapter = Class.new do
      def initialize = @token = "adapter-held-secret"
      def call(_request) = nil
    end.new

    yaml = NCP::Client.new(api_key: TEST_API_KEY, http_adapter: adapter).to_yaml

    refute_includes yaml, TEST_API_KEY
    refute_includes yaml, "adapter-held-secret"
    assert_equal "[redacted]", YAML.safe_load(yaml)["api_key"]
  end

  def test_keeps_the_key_out_of_serializers_that_walk_instance_variables
    refute_includes @client.to_yaml, TEST_API_KEY

    # Marshal refuses the object outright, which is also not a leak.
    begin
      refute_includes Marshal.dump(@client), TEST_API_KEY
    rescue TypeError => e
      refute_includes e.message, TEST_API_KEY
    end
  end

  # Everything a serializer could walk to: instance variables, Data members,
  # Hash and Array contents. The one place the key lives is a closure, which
  # none of them descend into.
  def test_does_not_hold_the_key_anywhere_a_serializer_can_walk
    reachable = [@client]
    seen = []

    until reachable.empty?
      object = reachable.shift
      next if seen.any? { |other| other.equal?(object) }

      seen << object

      refute_includes object, TEST_API_KEY if object.is_a?(String)

      reachable.concat(object.instance_variables.map { |name| object.instance_variable_get(name) })
      reachable.concat(object.to_h.values) if object.is_a?(Data)
      reachable.concat(object.to_a.flatten) if object.is_a?(Hash) || object.is_a?(Array)
    end

    assert_operator seen.size, :>, 5, "the walk did not reach the client's configuration"
  end

  def test_keeps_the_key_out_of_the_request_as_printed
    adapter = FakeAdapter.new([{ body: envelope(nonprofit_fixture) }])
    client_with(adapter).nonprofits.check("411787097")

    refute_includes adapter.requests.first.inspect, TEST_API_KEY
    assert_includes adapter.requests.first.headers["authorization"], TEST_API_KEY
  end
end

class UserAgentTest < Minitest::Test
  include TestSupport

  def test_identifies_the_sdk_language_and_version
    user_agent = NCP::Config.user_agent

    assert user_agent.start_with?("#{NCP::GEM_NAME}/#{NCP::VERSION} ")
    assert_includes user_agent, "ruby/#{RUBY_VERSION}"
  end

  def test_matches_the_name_and_version_the_gemspec_publishes
    spec = Gem::Specification.load(File.expand_path("../pactman-nonprofit-check-plus.gemspec", __dir__))

    assert_equal NCP::GEM_NAME, spec.name
    assert_equal NCP::VERSION, spec.version.to_s
  end

  def test_packages_no_file_outside_the_library
    spec = Gem::Specification.load(File.expand_path("../pactman-nonprofit-check-plus.gemspec", __dir__))

    Dir.chdir(File.expand_path("..", __dir__)) do
      assert_includes spec.files, "lib/pactman/nonprofit_check_plus.rb"
      assert(spec.files.all? { |file| file.start_with?("lib/") || %w[README.md LICENSE].include?(file) })
      assert_empty spec.runtime_dependencies
    end
  end
end
