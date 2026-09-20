# frozen_string_literal: true

require "json"
require "securerandom"
require "socket"

require_relative "fixtures"

# A stand-in for the Nonprofit Check Plus API, so the examples can be run in CI
# without a real key or network access.
#
# Only the two check endpoints are implemented, with the same envelope shape,
# auth header, batch limit, bulk matching semantics and cumulative check count
# as the real service. Records come from `fixtures.rb`.
#
# It speaks just enough HTTP/1.1 for that — one request per connection, a
# `Content-Length` body, `Connection: close` — on a thread per connection, so a
# held response does not block the next caller. The standard library carries no
# HTTP server since WEBrick left it, and this keeps the harness dependency-free.
#
#   ruby scripts/mock_server.rb 4010
class MockServer
  MAX_BULK_EINS = 50
  SINGLE_PATH = %r{\A/api/entities/nonprofitcheck/v1/us/ein/(\d{9})\z}
  BULK_PATH = "/api/entities/nonprofitcheckbulk/v1/us/eins"

  # How long the `slow` control EIN holds a response open, in seconds.
  SLOW_RESPONSE = 5
  # How many times the `transient_failure` control EIN fails before succeeding.
  TRANSIENT_FAILURES = 2

  STATUS_TEXT = { 200 => "OK", 400 => "Bad Request", 401 => "Unauthorized", 404 => "Not Found",
                  429 => "Too Many Requests", 503 => "Service Unavailable" }.freeze

  attr_reader :url

  # Starts the mock API in the background.
  #
  # @param port [Integer] 0 picks a free port.
  # @param api_key [String] the key the server accepts.
  def self.start(port: 0, api_key: ENV.fetch("MOCK_API_KEY", "mock-key"))
    new(port: port, api_key: api_key).tap(&:start)
  end

  def initialize(port:, api_key:)
    @server = TCPServer.new("127.0.0.1", port)
    @url = "http://127.0.0.1:#{@server.addr[1]}"
    @valid_authorization = "Bearer #{api_key}"
    @lock = Mutex.new
    @threads = []

    # Mirrors the real service: a running total for the billing cycle, not the
    # size of the current request.
    @checks_used_this_cycle = 0
    @transient_failures_left = TRANSIENT_FAILURES
  end

  def start
    @acceptor = Thread.new do
      loop do
        socket = @server.accept
        track(Thread.new(socket) { |connection| serve(connection) })
      end
    rescue IOError, Errno::EBADF
      nil # closed
    end

    self
  end

  # Stops the server and abandons any held response, leaving no thread behind.
  def close
    @server.close unless @server.closed?
    @acceptor&.join(1)
    @lock.synchronize { @threads.dup }.each(&:kill)
  end

  private

  def track(thread)
    @lock.synchronize do
      @threads.select!(&:alive?)
      @threads << thread
    end
  end

  def serve(socket)
    request = read_request(socket)
    return if request.nil?

    status, body, headers = route(request)
    write_response(socket, status, body, headers)
  rescue IOError, SystemCallError
    nil # the client went away, as a timed-out client does
  ensure
    socket.close unless socket.closed?
  end

  def read_request(socket)
    method, target = socket.gets&.split
    return nil if method.nil?

    headers = {}

    while (line = socket.gets) && line != "\r\n"
      name, value = line.split(":", 2)
      headers[name.strip.downcase] = value.to_s.strip
    end

    length = headers.fetch("content-length", "0").to_i
    { method: method, path: target.to_s.split("?").first, headers: headers,
      body: length.positive? ? socket.read(length) : "" }
  end

  def write_response(socket, status, body, headers)
    payload = JSON.generate(body)
    head = { "Content-Type" => "application/json", "Content-Length" => payload.bytesize.to_s,
             "X-Request-Id" => "mock-#{SecureRandom.hex(4)}", "Connection" => "close" }.merge(headers)

    socket.write("HTTP/1.1 #{status} #{STATUS_TEXT.fetch(status, "Unknown")}\r\n")
    head.each { |name, value| socket.write("#{name}: #{value}\r\n") }
    socket.write("\r\n#{payload}")
  end

  def route(request)
    if request[:headers]["authorization"] != @valid_authorization
      return [401, { code: 401, message: "Unauthorized",
                     errors: [{ resource: "nonprofitcheck", reason: "Invalid API Key" }], data: nil }, {}]
    end

    single = SINGLE_PATH.match(request[:path])

    return handle_single(single[1]) if request[:method] == "GET" && single
    return handle_bulk(parse_json(request[:body])) if request[:method] == "POST" && request[:path] == BULK_PATH

    [404, { code: 404, message: "Not Found", errors: nil, data: nil }, {}]
  end

  def parse_json(text)
    text.strip.empty? ? nil : JSON.parse(text)
  rescue JSON::ParserError
    nil
  end

  # The success envelope. `nonprofit_check_count` is the billing-cycle total.
  def envelope(data, errors, check_count)
    { code: 200, message: "OK", errors: errors, data: data, timeTaken: rand(2..41),
      nonprofit_check_count: check_count }
  end

  def error_envelope(code, message, errors)
    { code: code, message: message, errors: errors, data: nil, timeTaken: 1,
      nonprofit_check_count: @lock.synchronize { @checks_used_this_cycle } }
  end

  def count(delta)
    @lock.synchronize { @checks_used_this_cycle += delta }
  end

  def handle_single(ein)
    case ein
    when Fixtures::CONTROL_EINS[:rate_limited]
      [429, error_envelope(429, "Too Many Requests", [{ resource: "nonprofitcheck", reason: "Rate limit exceeded" }]),
       { "Retry-After" => "1" }]
    when Fixtures::CONTROL_EINS[:transient_failure]
      transient_failure
    when Fixtures::CONTROL_EINS[:slow]
      sleep SLOW_RESPONSE
      [200, envelope(Fixtures.organization(Fixtures::EINS[:public_charity]), nil, count(1)), {}]
    else
      found = Fixtures.organization(ein)

      if found.nil?
        return [404, error_envelope(404, "Not Found", [{ resource: "nonprofitcheck",
                                                         reason: "A nonprofit with this EIN does not exist in our records" }]), {}]
      end

      [200, envelope(found, nil, count(1)), {}]
    end
  end

  def transient_failure
    failing = @lock.synchronize do
      if @transient_failures_left.positive?
        @transient_failures_left -= 1
        true
      else
        @transient_failures_left = TRANSIENT_FAILURES
        false
      end
    end

    if failing
      return [503, error_envelope(503, "Service Unavailable",
                                  [{ resource: "nonprofitcheck", reason: "Upstream temporarily unavailable" }]), {}]
    end

    [200, envelope(Fixtures.organization(Fixtures::EINS[:public_charity]), nil, count(1)), {}]
  end

  def handle_bulk(eins)
    unless eins.is_a?(Array)
      return bad_request("The nonprofit check bulk API expects an array of EINs as part of the HTTP POST request body")
    end

    return bad_request("A maximum of #{MAX_BULK_EINS} EINs can be supplied to the nonprofit check bulk API") if eins.size > MAX_BULK_EINS

    organizations = Fixtures.organizations

    # The real service selects with `WHERE ein IN (...)`: duplicates collapse to
    # one row and the result order is the database's, not the request's. Sorting
    # here keeps that difference visible instead of accidentally matching.
    matched = eins.uniq.select { |ein| organizations.key?(ein) }.sort
    not_found = eins.reject { |ein| organizations.key?(ein) }

    # Every submitted EIN is counted, duplicates included; unmatched EINs are
    # refunded, so the count reflects records actually served.
    total = count(eins.size - not_found.size)
    reason = "There are no matching nonprofits in our records for this set of EINs"

    if matched.empty?
      return [404, error_envelope(404, "Not Found", [{ resource: "nonprofitcheckbulk", reason: reason }]),
              {}]
    end

    errors = not_found.empty? ? nil : [{ resource: "nonprofitcheckbulk", reason: reason, code: 404, eins: not_found }]

    [200, envelope(matched.map { |ein| organizations.fetch(ein) }, errors, total), {}]
  end

  def bad_request(reason)
    [400, error_envelope(400, "Bad Request", [{ resource: "nonprofitcheckbulk", reason: reason }]), {}]
  end
end

if $PROGRAM_NAME == __FILE__
  server = MockServer.new(port: Integer(ARGV.fetch(0, "4010")), api_key: ENV.fetch("MOCK_API_KEY", "mock-key"))
  server.start
  puts "Mock Pactman API listening on #{server.url}"

  trap("INT") do
    server.close
    exit
  end

  sleep
end
