# frozen_string_literal: true

module Pactman
  module NonprofitCheckPlus
    # The seam between the SDK and whatever carries its bytes.
    #
    # An HTTP adapter is any object with `#call(request)` that returns an object
    # with `#status`, `#headers` and `#body`. The default, {NetHttpAdapter}, uses
    # the standard library and nothing else. Supply your own through the client's
    # `http_adapter:` option to route through a connection pool, a proxy library
    # or a test double.
    #
    # An adapter reports failure by raising:
    #
    # - a `Timeout::Error` (including `Net::OpenTimeout` and `Net::ReadTimeout`)
    #   when the request's `timeout` expired, which the SDK raises as
    #   {TimeoutError};
    # - any other `StandardError` when no response arrived, which the SDK raises
    #   as {NetworkError} with the adapter's exception as its `cause`.
    #
    # Exceptions outside `StandardError` — a `Thread#kill`, a `Timeout.timeout`
    # interrupt, a fiber scheduler stopping the task — are the caller cancelling,
    # and pass through the SDK untouched.
    module Http
      # One HTTP attempt, as the SDK hands it to an adapter.
      #
      # The `Authorization` header is present in {#headers}, because the adapter
      # has to send it, and absent from {#inspect}, because nothing should print it.
      class Request
        # @return [Symbol] `:get` or `:post`.
        attr_reader :http_method
        # @return [String] the absolute URL.
        attr_reader :url
        # @return [Hash{String => String}] header names are lowercase.
        attr_reader :headers
        # @return [String, nil] the JSON body, for a POST.
        attr_reader :body
        # @return [Numeric] seconds this attempt may take, end to end.
        attr_reader :timeout

        def initialize(http_method:, url:, headers:, body:, timeout:)
          @http_method = http_method
          @url = url
          @headers = headers.freeze
          @body = body
          @timeout = timeout
        end

        def inspect
          shown = headers.to_h { |name, value| [name, name == "authorization" ? "[redacted]" : value] }

          "#<#{self.class.name} #{http_method.upcase} #{url} headers=#{shown.inspect} timeout=#{timeout}>"
        end
        alias to_s inspect
      end

      # What an adapter returns.
      #
      # @!attribute [r] status
      #   @return [Integer]
      # @!attribute [r] headers
      #   @return [Hash{String => String}] any case; the SDK compares names case-insensitively.
      # @!attribute [r] body
      #   @return [String] the response body, empty when there was none.
      Response = Data.define(:status, :headers, :body)

      # The default adapter: `Net::HTTP`, one connection per attempt.
      #
      # The request's `timeout` is an end-to-end deadline, not a per-read one.
      # `Net::HTTP` on its own only bounds each socket operation, so a server that
      # trickles a byte just inside every read timeout would hold a request open
      # indefinitely; the deadline is carried through the connect, the write and
      # every chunk of the body instead.
      #
      # Proxies are read from the environment (`https_proxy`, `no_proxy`), as
      # `Net::HTTP` does by default.
      class NetHttpAdapter
        # @param request [Request]
        # @return [Response]
        def call(request)
          uri = URI.parse(request.url)
          deadline = monotonic + request.timeout
          http = connection_for(uri, deadline)

          http.start do |connection|
            perform(connection, build(request, uri), deadline)
          end
        end

        def inspect
          "#<#{self.class.name}>"
        end

        private

        def connection_for(uri, deadline)
          http = Net::HTTP.new(uri.hostname, uri.port)

          http.use_ssl = uri.scheme == "https"
          # Net::HTTP retries an idempotent request once on a read timeout or a
          # reset, invisibly. That doubles the deadline and the billing, and it
          # is the SDK's retry policy that decides whether to try again.
          http.max_retries = 0
          http.open_timeout = remaining(deadline)
          http
        end

        def build(request, uri)
          net_request = request.http_method == :post ? Net::HTTP::Post.new(uri) : Net::HTTP::Get.new(uri)

          request.headers.each { |name, value| net_request[name] = value }
          net_request.body = request.body unless request.body.nil?
          net_request
        end

        def perform(connection, net_request, deadline)
          connection.write_timeout = remaining(deadline)
          connection.read_timeout = remaining(deadline)

          body = +""
          status = nil
          headers = nil

          connection.request(net_request) do |response|
            status = response.code.to_i
            headers = response.each_header.to_h

            response.read_body do |chunk|
              body << chunk
              connection.read_timeout = remaining(deadline)
            end
          end

          Response.new(status: status, headers: headers, body: body.force_encoding(Encoding::UTF_8))
        end

        # Seconds left before the deadline. Raises once there are none, so a slow
        # trickle fails at the deadline rather than at the next quiet read.
        def remaining(deadline)
          left = deadline - monotonic

          raise Net::ReadTimeout unless left.positive?

          left
        end

        def monotonic
          Process.clock_gettime(Process::CLOCK_MONOTONIC)
        end
      end
    end
  end
end
