# frozen_string_literal: true

require_relative "test_helper"
require "socket"

# An adapter that waits out the request's deadline and then reports it, as a
# real socket read would.
HANGING = lambda do |request|
  sleep request.timeout
  raise Net::ReadTimeout
end

class TimeoutTest < Minitest::Test
  include TestSupport

  def test_documents_a_finite_default_timeout
    assert_predicate NCP::DEFAULT_TIMEOUT, :finite?
    assert_equal NCP::DEFAULT_TIMEOUT, NCP::Client.new(api_key: TEST_API_KEY).timeout
  end

  def test_raises_a_timeout_error_when_the_endpoint_exceeds_the_timeout
    client = client_with(FakeAdapter.new([HANGING]), timeout: 0.01, retry: false)

    error = assert_raises(NCP::TimeoutError) { client.nonprofits.check("411787097") }

    assert_equal :timeout, error.category
    assert_in_delta 0.01, error.timeout
    assert_kind_of Timeout::Error, error.cause
  end

  def test_lets_a_per_request_timeout_override_the_client_default
    adapter = FakeAdapter.new([HANGING])
    client = client_with(adapter, timeout: 5, retry: false)
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    error = assert_raises(NCP::TimeoutError) { client.nonprofits.check("411787097", timeout: 0.015) }

    assert_in_delta 0.015, error.timeout
    assert_in_delta 0.015, adapter.requests.first.timeout
    assert_operator Process.clock_gettime(Process::CLOCK_MONOTONIC) - started, :<, 1
  end

  def test_rejects_a_per_request_timeout_that_disables_the_deadline
    adapter = FakeAdapter.new([{ body: envelope(nonprofit_fixture) }])

    assert_raises(NCP::ConfigurationError) { client_with(adapter).nonprofits.check("411787097", timeout: 0) }
    assert_empty adapter.requests
  end

  def test_retries_a_timeout_when_the_retry_policy_allows_it
    adapter = FakeAdapter.new([HANGING, { body: envelope(nonprofit_fixture) }])
    client = client_with(adapter, timeout: 0.01, retry: { max_retries: 1, jitter: false, initial_delay: 0.001 })

    result = client.nonprofits.check("411787097")

    assert_equal 2, adapter.requests.size
    assert_equal "411787097", result.nonprofit.ein
  end
end

# Cancellation is Ruby's own. What the SDK owes it is to stay out of the way: an
# interrupt it did not raise is never converted, never retried, never swallowed.
class CancellationTest < Minitest::Test
  include TestSupport

  class CallerCancelled < Exception; end # rubocop:disable Lint/InheritException -- a caller's own interrupt

  def test_an_interrupt_during_the_request_propagates_untouched_and_is_not_retried
    adapter = FakeAdapter.new([->(_request) { raise CallerCancelled }])
    client = client_with(adapter, retry: { max_retries: 3 })

    assert_raises(CallerCancelled) { client.nonprofits.check("411787097") }
    assert_equal 1, adapter.requests.size
  end

  def test_an_interrupt_while_waiting_to_retry_stops_the_planned_retries
    adapter = FakeAdapter.new([{ status: 503, body: {} }])
    hooks = NCP::TransportHooks.new(sleep: ->(_seconds) { raise CallerCancelled })
    client = NCP::Client.new(api_key: TEST_API_KEY, base_url: BASE_URL, http_adapter: adapter, hooks: hooks,
                             retry: { max_retries: 5 })

    assert_raises(CallerCancelled) { client.nonprofits.check("411787097") }
    assert_equal 1, adapter.requests.size
  end

  def test_timeout_timeout_around_a_call_raises_rubys_timeout_not_the_sdks
    adapter = FakeAdapter.new([->(_request) { sleep 5 }])
    client = client_with(adapter, retry: { max_retries: 3 })

    error = assert_raises(Timeout::Error) { Timeout.timeout(0.05) { client.nonprofits.check("411787097") } }

    refute_kind_of NCP::Error, error
    assert_equal 1, adapter.requests.size
  end

  def test_killing_the_thread_leaves_nothing_running
    started = Queue.new
    adapter = FakeAdapter.new([lambda do |_request|
      started << true
      sleep 5
    end])
    client = client_with(adapter)
    worker = Thread.new { client.nonprofits.check("411787097") }

    started.pop
    worker.kill
    worker.join(1)

    refute_predicate worker, :alive?
    assert_equal 1, adapter.requests.size
  end
end

# The default adapter against a real socket, for the deadline behaviour a fake
# cannot show.
class NetHttpAdapterTest < Minitest::Test
  include TestSupport

  def setup
    @server = TCPServer.new("127.0.0.1", 0)
    @connections = Queue.new
    @threads = []
  end

  def teardown
    @threads.each(&:kill)
    @server.close
  end

  def serve(&handler)
    @threads << Thread.new do
      loop do
        socket = @server.accept
        @connections << true
        @threads << Thread.new(socket) do |client|
          handler.call(client, read_request(client))
        ensure
          client.close unless client.closed?
        end
      end
    rescue IOError
      nil
    end
  end

  def client(**)
    NCP::Client.new(api_key: TEST_API_KEY, base_url: "http://127.0.0.1:#{@server.addr[1]}", **)
  end

  def test_sends_the_request_and_reads_the_response
    received = Queue.new

    serve do |socket, request|
      received << request
      body = JSON.generate(envelope([nonprofit_fixture]))
      socket.write("HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nX-Request-Id: sock-1\r\n" \
                   "Content-Length: #{body.bytesize}\r\nConnection: close\r\n\r\n#{body}")
    end

    result = client.nonprofits.check_bulk(%w[41-1787097])
    request = received.pop

    assert_equal "POST /api/entities/nonprofitcheckbulk/v1/us/eins", request[:line].split[0, 2].join(" ")
    assert_equal "Bearer #{TEST_API_KEY}", request[:headers]["authorization"]
    assert_equal "application/json", request[:headers]["content-type"]
    assert_match %r{\Apactman-nonprofit-check-plus/}, request[:headers]["user-agent"]
    assert_equal '["411787097"]', request[:body]
    assert_equal "sock-1", result.request_id
    assert_equal "EXAMPLE NONPROFIT", result.organizations.first.organization_name
  end

  def test_times_out_a_server_that_never_answers_and_does_not_resend
    serve { |_socket, _request| sleep 5 }

    error = assert_raises(NCP::TimeoutError) { client(timeout: 0.2, retry: false).nonprofits.check("411787097") }

    assert_kind_of Net::ReadTimeout, error.cause
    assert_equal 1, @connections.size, "Net::HTTP retried the request on its own"
  end

  def test_enforces_the_deadline_end_to_end_against_a_trickling_body
    serve do |socket, _request|
      socket.write("HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: 100\r\n\r\n")
      100.times do
        socket.write(" ")
        sleep 0.05
      end
    end

    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    assert_raises(NCP::TimeoutError) { client(timeout: 0.3, retry: false).nonprofits.check("411787097") }
    assert_operator Process.clock_gettime(Process::CLOCK_MONOTONIC) - started, :<, 1.5
  end

  def test_reports_a_refused_connection_as_a_network_error
    port = @server.addr[1]
    @server.close

    unreachable = NCP::Client.new(api_key: TEST_API_KEY, base_url: "http://127.0.0.1:#{port}", retry: false)
    error = assert_raises(NCP::NetworkError) { unreachable.nonprofits.check("411787097") }

    assert_kind_of SystemCallError, error.cause
    @server = TCPServer.new("127.0.0.1", 0)
  end

  private

  def read_request(socket)
    line = socket.gets.to_s.strip
    headers = {}

    while (header = socket.gets) && header != "\r\n"
      name, value = header.split(":", 2)
      headers[name.strip.downcase] = value.to_s.strip
    end

    { line: line, headers: headers, body: socket.read(headers.fetch("content-length", "0").to_i) }
  end
end
