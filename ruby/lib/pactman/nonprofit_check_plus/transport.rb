# frozen_string_literal: true

module Pactman
  module NonprofitCheckPlus
    # Hooks the test suite substitutes for real time. Not part of the public API
    # and not covered by semantic versioning; do not depend on it.
    #
    # @api private
    TransportHooks = Data.define(:sleep, :random, :monotonic) do
      def initialize(sleep: nil, random: nil, monotonic: nil)
        super
      end
    end

    # HTTP transport: authentication headers, timeouts, retries with jittered
    # backoff, `Retry-After` handling, client-side throttling, and mapping
    # responses to the error taxonomy.
    #
    # The API key lives in a closure, not an instance variable. It is written
    # into the `Authorization` header at send time and is never reachable from
    # `inspect`, `pp`, `to_yaml`, `Marshal`, an error, or any diagnostic output.
    #
    # @api private
    class Transport
      # A parsed HTTP response plus the metadata callers need.
      Response = Data.define(:status, :request_id, :body, :attempts)

      # Headers the SDK owns. A default or per-request header of the same name,
      # in any case, is replaced rather than sent alongside.
      RESERVED_HEADERS = %w[accept user-agent authorization content-type].freeze

      REQUEST_ID_HEADERS = %w[x-request-id x-correlation-id request-id].freeze

      # @param api_key [String]
      # @param config [ResolvedConfig]
      # @param hooks [TransportHooks, nil]
      def initialize(api_key, config, hooks = nil)
        @authorization = self.class.send(:credential, api_key)
        @config = config
        @sleep = hooks&.sleep || ->(seconds) { Kernel.sleep(seconds) }
        @random = hooks&.random || -> { Kernel.rand }
        @monotonic = hooks&.monotonic || -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }
        @throttle_lock = Mutex.new
        @next_request_at = nil
      end

      # Sends one logical request, retrying under the policy in force.
      #
      # @return [Response]
      # @raise [ApiError, TimeoutError, NetworkError]
      def perform(http_method:, path:, body: nil, timeout: nil, retry_option: nil, headers: nil)
        policy = Config.resolve_retry(@config.retry_policy, retry_option)
        request = build_request(http_method, path, body, timeout, headers)
        attempt = 0

        loop do
          attempt += 1
          throttle

          response, error, cause = attempt_once(request, attempt)

          if response.nil?
            raise error, cause: cause if attempt > policy.max_retries

            wait_before_retry(attempt, policy, nil)
            next
          end

          outcome = read_response(response, attempt)
          return outcome if outcome.is_a?(Response)

          raise outcome if attempt > policy.max_retries || !policy.retryable_status?(outcome.status)

          wait_before_retry(attempt, policy, outcome.retry_after_seconds)
        end
      end

      def inspect
        "#<#{self.class.name} #{@config.base_url}>"
      end

      # Delay before the next attempt, in seconds.
      #
      # A valid `Retry-After` wins outright. Otherwise the delay grows
      # exponentially from `initial_delay`, is capped at `max_delay`, and — with
      # jitter on — is randomized across the whole range so concurrent clients
      # spread out. Rounded to the millisecond.
      #
      # @param attempt [Integer] the attempt that just failed, starting at 1.
      # @param policy [RetryPolicy]
      # @param retry_after_seconds [Numeric, nil]
      # @param random [#call] returns a Float in `[0, 1)`.
      # @return [Float]
      def self.compute_retry_delay(attempt, policy, retry_after_seconds, random = -> { Kernel.rand })
        if policy.respect_retry_after && retry_after_seconds && retry_after_seconds >= 0
          return retry_after_seconds.to_f.round(3)
        end

        exponential = policy.initial_delay * (policy.backoff_factor**(attempt - 1))
        capped = [exponential, policy.max_delay].min

        (policy.jitter ? random.call * capped : capped).to_f.round(3)
      end

      # Reads `Retry-After` as either a delay in seconds or an HTTP date.
      #
      # @param headers [Hash{String => String}] lowercase names.
      # @param now [Time]
      # @return [Numeric, nil] seconds, or `nil` when absent or unreadable.
      def self.read_retry_after(headers, now = Time.now)
        raw = headers["retry-after"]
        return nil if raw.nil?

        trimmed = raw.strip
        return nil if trimmed.empty?

        seconds = Integer(trimmed, 10, exception: false) || Float(trimmed, exception: false)
        return seconds if seconds&.finite? && seconds >= 0

        date = parse_http_date(trimmed)
        date && [0, date - now].max
      end

      # Normalizes the envelope's `errors` into a list.
      #
      # @return [Array<ApiErrorDetail>]
      def self.normalize_api_errors(errors)
        case errors
        when Array then errors.grep(Hash).map { |entry| ApiErrorDetail.new(entry) }
        when Hash then [ApiErrorDetail.new(errors)]
        when String then errors.strip.empty? ? [] : [ApiErrorDetail.new({ "reason" => errors })]
        else []
        end
      end

      def self.parse_http_date(value)
        Time.httpdate(value)
      rescue ArgumentError
        begin
          Time.rfc2822(value)
        rescue ArgumentError
          nil
        end
      end
      private_class_method :parse_http_date

      def self.credential(api_key)
        header = "Bearer #{api_key}".freeze

        -> { header }
      end
      private_class_method :credential

      private

      def build_request(http_method, path, body, timeout, headers)
        Http::Request.new(
          http_method: http_method,
          url: "#{@config.base_url}#{path}",
          headers: build_headers(Config.validate_headers(headers, "headers"), !body.nil?),
          body: body.nil? ? nil : JSON.generate(body),
          timeout: timeout.nil? ? @config.timeout : Config.validate_timeout(timeout)
        )
      end

      # The parsed success, or the {ApiError} a non-2xx response maps to.
      def read_response(response, attempt)
        status = response.status.to_i
        headers = normalize_headers(response.headers)
        parsed = parse_body(response.body)
        request_id = read_request_id(headers)

        return Response.new(status:, request_id:, body: parsed, attempts: attempt) if (200..299).cover?(status)

        api_error(status, parsed, request_id, self.class.read_retry_after(headers), attempt)
      end

      def build_headers(per_request, has_body)
        headers = {}

        [@config.default_headers, per_request].each do |source|
          source.each { |name, value| headers[name.downcase] = value }
        end

        RESERVED_HEADERS.each { |name| headers.delete(name) }

        headers["accept"] = "application/json"
        headers["user-agent"] = @config.user_agent
        headers["authorization"] = @authorization.call
        headers["content-type"] = "application/json" if has_body
        headers
      end

      # One attempt. Returns `[response]`, or `[nil, error, cause]` when no
      # response arrived. Only `StandardError` is rescued: anything else is the
      # caller cancelling, and it is theirs.
      def attempt_once(request, attempt)
        [@config.http_adapter.call(request)]
      rescue ::Timeout::Error => e
        [nil, TimeoutError.new("The request timed out after #{format("%g", request.timeout)}s.",
                               timeout: request.timeout, attempts: attempt), e]
      rescue StandardError => e
        [nil, NetworkError.new("The request to the Pactman API failed: #{e.message}", attempts: attempt), e]
      end

      # Spaces requests when `max_requests_per_second` is configured.
      def throttle
        limit = @config.max_requests_per_second
        return if limit.nil?

        wait = @throttle_lock.synchronize do
          now = @monotonic.call
          scheduled_at = @next_request_at.nil? ? now : [now, @next_request_at].max
          @next_request_at = scheduled_at + (1.0 / limit)
          scheduled_at - now
        end

        @sleep.call(wait) if wait.positive?
      end

      def wait_before_retry(attempt, policy, retry_after_seconds)
        @sleep.call(self.class.compute_retry_delay(attempt, policy, retry_after_seconds, @random))
      end

      def normalize_headers(headers)
        (headers || {}).to_h do |name, value|
          [name.to_s.downcase, value.is_a?(Array) ? value.join(", ") : value.to_s]
        end
      end

      def read_request_id(headers)
        REQUEST_ID_HEADERS.lazy.filter_map { |name| headers[name] }.first
      end

      # The parsed JSON, the text itself when it is not JSON, or `nil` when there
      # was no body. An unparseable body is still evidence, so it is kept.
      def parse_body(body)
        text = body.to_s.dup.force_encoding(Encoding::UTF_8)
        text = text.scrub unless text.valid_encoding?
        return nil if text.strip.empty?

        begin
          JSON.parse(text)
        rescue JSON::ParserError
          text
        end
      end

      def api_error(status, parsed, request_id, retry_after, attempts)
        envelope = parsed.is_a?(Hash) ? parsed : nil
        api_errors = self.class.normalize_api_errors(envelope&.fetch("errors", nil))

        ApiError.for_status(
          status: status,
          api_message: api_message(api_errors, envelope, parsed),
          api_code: envelope && envelope["code"].is_a?(Numeric) ? envelope["code"] : nil,
          api_errors: api_errors,
          request_id: request_id,
          retry_after_seconds: retry_after,
          raw: parsed,
          attempts: attempts
        )
      end

      def api_message(api_errors, envelope, parsed)
        reasons = api_errors.map(&:reason).select { |reason| reason.is_a?(String) && !reason.strip.empty? }

        return reasons.join("; ") unless reasons.empty?
        return envelope["message"] if envelope && envelope["message"].is_a?(String)

        parsed.strip[0, 500] if parsed.is_a?(String) && !parsed.strip.empty?
      end
    end
  end
end
