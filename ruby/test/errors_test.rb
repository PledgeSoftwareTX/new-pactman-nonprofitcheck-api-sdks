# frozen_string_literal: true

require_relative "test_helper"
require "pp"
require "stringio"

class ErrorMappingTest < Minitest::Test
  include TestSupport

  def check_with(stub, timeout: 30)
    client_with(FakeAdapter.new([stub]), retry: false, timeout: timeout).nonprofits.check("411787097")
  end

  MAPPING = {
    400 => [NCP::BadRequestError, :bad_request],
    401 => [NCP::AuthenticationError, :authentication],
    403 => [NCP::AuthorizationError, :authorization],
    404 => [NCP::NotFoundError, :not_found],
    429 => [NCP::RateLimitError, :rate_limit],
    500 => [NCP::ServerError, :server],
    503 => [NCP::ServerError, :server]
  }.freeze

  def test_maps_each_http_status_to_the_documented_class_and_category
    MAPPING.each do |status, (error_class, category)|
      stub = { status: status, body: { "code" => status, "message" => "failed", "errors" => nil, "data" => nil } }
      error = assert_raises(error_class) { check_with(stub) }

      assert_equal category, error.category
      assert_equal :api, error.origin
      assert_equal status, error.status
      assert_kind_of NCP::ApiError, error
    end
  end

  def test_falls_back_to_a_general_api_error_for_an_unexpected_status
    error = assert_raises(NCP::ApiError) { check_with({ status: 418, body: { "message" => "I'm a teapot" } }) }

    assert_instance_of NCP::ApiError, error
    assert_equal :api, error.category
    assert_equal 418, error.status
    assert_equal "I'm a teapot", error.api_message
    assert_equal "I'm a teapot", error.message
  end

  def test_uses_a_default_message_when_the_body_has_none
    error = assert_raises(NCP::AuthenticationError) { check_with({ status: 401, body: {} }) }

    assert_equal "The Pactman API key was rejected.", error.message
  end

  def test_keeps_response_metadata_when_the_body_cannot_be_deserialized
    stub = { status: 502, body_text: "<html>gateway error</html>",
             headers: { "content-type" => "text/html", "X-Request-Id" => "req-html-1" } }
    error = assert_raises(NCP::ServerError) { check_with(stub) }

    assert_equal 502, error.status
    assert_equal "req-html-1", error.request_id
    assert_equal "<html>gateway error</html>", error.raw
    assert_equal "<html>gateway error</html>", error.api_message
  end

  def test_exposes_retry_after_on_a_429
    error = assert_raises(NCP::RateLimitError) do
      check_with({ status: 429, body: { "code" => 429, "message" => "Too Many Requests" },
                   headers: { "retry-after" => "12" } })
    end

    assert_equal :rate_limit, error.category
    assert_equal 12, error.retry_after_seconds
  end

  def test_retains_the_request_id_on_a_server_error
    error = assert_raises(NCP::ServerError) do
      check_with({ status: 500, body: { "code" => 500 }, headers: { "x-request-id" => "req-abc-123" } })
    end

    assert_equal "req-abc-123", error.request_id
  end

  def test_falls_back_through_the_correlation_headers
    error = assert_raises(NCP::ServerError) do
      check_with({ status: 500, body: {}, headers: { "X-Correlation-Id" => "corr-9" } })
    end

    assert_equal "corr-9", error.request_id
  end

  def test_surfaces_the_api_reason_list_without_string_parsing
    body = {
      "code" => 400,
      "message" => "Bad Request",
      "errors" => [
        { "resource" => "nonprofitcheck", "reason" => "Invalid EIN format", "code" => 400 },
        { "resource" => "nonprofitcheck", "reason" => "EIN must contain 9 digits" }
      ],
      "data" => nil
    }
    error = assert_raises(NCP::BadRequestError) { check_with({ status: 400, body: body }) }

    assert_equal 2, error.api_errors.size
    assert_equal "Invalid EIN format", error.api_errors.first.reason
    assert_equal 400, error.api_code
    assert_equal "Invalid EIN format; EIN must contain 9 digits", error.message
  end

  def test_reports_transport_failures_as_network_errors_with_the_cause
    failure = Errno::ECONNREFUSED.new("connect(2)")
    error = assert_raises(NCP::NetworkError) { check_with(failure) }

    assert_equal :network, error.category
    assert_equal :local, error.origin
    assert_same failure, error.cause
  end

  def test_distinguishes_local_errors_from_api_errors
    client = client_with(FakeAdapter.new([{ status: 400, body: { "message" => "Bad Request" } }]), retry: false)

    local = assert_raises(NCP::ValidationError) { client.nonprofits.check("bad-ein") }
    remote = assert_raises(NCP::BadRequestError) { client.nonprofits.check("411787097") }

    assert_equal :local, local.origin
    assert_equal :validation, local.category
    assert_equal :api, remote.origin
    assert_kind_of NCP::Error, local
    assert_kind_of NCP::Error, remote
  end

  def test_is_rescuable_through_the_common_base_class
    assert_raises(NCP::Error) { check_with({ status: 401, body: {} }) }
  end

  def test_every_category_is_carried_by_some_error_class
    carried = [NCP::ConfigurationError.new("x").category, NCP::ValidationError.new("x").category,
               NCP::TimeoutError.new("x", timeout: 1).category, NCP::NetworkError.new("x").category,
               *[NCP::ApiError, NCP::BadRequestError, NCP::AuthenticationError, NCP::AuthorizationError,
                 NCP::NotFoundError, NCP::RateLimitError, NCP::ServerError].map(&:category)]

    assert_equal NCP::ErrorCategory.all.sort, carried.sort
  end
end

class ErrorCredentialSafetyTest < Minitest::Test
  include TestSupport

  STUBS = {
    "401" => { status: 401, body: { "code" => 401, "message" => "Unauthorized" } },
    "429" => { status: 429, body: { "code" => 429 }, headers: { "retry-after" => "3" } },
    "500" => { status: 500, body: { "code" => 500 } },
    "network failure" => SocketError.new("getaddrinfo: nodename nor servname provided")
  }.freeze

  def test_keeps_the_api_key_out_of_every_diagnostic_surface
    STUBS.each do |label, stub|
      client = client_with(FakeAdapter.new([stub]), retry: false)
      error = assert_raises(NCP::Error, label) { client.nonprofits.check("411787097") }

      surfaces_of(error).each { |surface| refute_includes surface, TEST_API_KEY, label }
    end
  end

  def test_keeps_the_api_key_out_of_a_timeout_error
    hanging = lambda do |request|
      sleep request.timeout
      raise Net::ReadTimeout
    end
    client = client_with(FakeAdapter.new([hanging]), retry: false, timeout: 0.01)
    error = assert_raises(NCP::TimeoutError) { client.nonprofits.check("411787097") }

    surfaces_of(error).each { |surface| refute_includes surface, TEST_API_KEY }
  end

  private

  def surfaces_of(error)
    printed = StringIO.new
    PP.pp(error, printed)

    [error.message, error.to_s, error.inspect, error.full_message, printed.string, error.to_h.to_s,
     error.to_json, (error.backtrace || []).join("\n"), error.cause.inspect]
  end
end
