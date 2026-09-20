# frozen_string_literal: true

module Pactman
  module NonprofitCheckPlus
    # Nonprofit lookups. Reached through {Client#nonprofits}.
    class NonprofitsResource
      # @api private
      def initialize(transport)
        @transport = transport
      end

      # Checks a single nonprofit by EIN.
      #
      # The EIN is normalized and validated locally first; a malformed EIN raises
      # {ValidationError} without sending a request.
      #
      # @example
      #   result = client.nonprofits.check("41-1787097")
      #   puts result.nonprofit&.organization_name, result.check_count
      #
      # @param ein [String]
      # @param timeout [Numeric, nil] overrides the client's timeout, in seconds.
      # @param headers [Hash{String => String}, nil] extra headers; cannot override `Authorization`.
      # @option options [false, Hash, RetryPolicy] :retry overrides the client's retry policy.
      # @return [SingleCheckResult]
      # @raise [ValidationError, ApiError, TimeoutError, NetworkError]
      def check(ein, timeout: nil, headers: nil, **options)
        retry_option = request_retry(options)
        normalized = EIN.normalize(ein)

        # Nine digits, so there is nothing in it to escape.
        response = @transport.perform(
          http_method: :get,
          path: SINGLE_CHECK_PATH.sub("{ein}", normalized),
          timeout: timeout,
          retry_option: retry_option,
          headers: headers
        )

        SingleCheckResult.new(nonprofit: extract_nonprofit(envelope_data(response.body)), **base_result(response))
      end

      # Checks up to {MAX_BULK_EINS} nonprofits in one request.
      #
      # Every EIN is normalized and validated before anything is sent; if any one
      # fails, the whole call raises {ValidationError} identifying the offending
      # index, and no request is made. EINs are sent in the order supplied and
      # duplicates are kept unless `dedupe:` is set — but the API matches by set
      # membership, so the response is not ordered to match and a repeated EIN
      # comes back once. Index `organizations` by `ein` rather than pairing
      # positionally.
      #
      # EINs the API has no record for are not an error: they arrive as HTTP 200
      # with the missing values in `not_found_eins`.
      #
      # @example
      #   result = client.nonprofits.check_bulk(["41-1787097", "996589560"])
      #   result.organizations.each { |org| puts org.ein }
      #   puts "no record for: #{result.not_found_eins.join(', ')}"
      #
      # @param eins [Array<String>]
      # @param dedupe [Boolean] remove duplicate EINs before sending, keeping
      #   first-seen order. Off by default: duplicates are sent exactly as
      #   supplied, because each one consumes quota and silently dropping them
      #   would misreport what was checked.
      # @param timeout [Numeric, nil]
      # @param headers [Hash{String => String}, nil]
      # @option options [false, Hash, RetryPolicy] :retry
      # @return [BulkCheckResult]
      # @raise [ValidationError, ApiError, TimeoutError, NetworkError]
      def check_bulk(eins, dedupe: false, timeout: nil, headers: nil, **options)
        retry_option = request_retry(options)
        payload = bulk_payload(eins, dedupe)

        response = @transport.perform(
          http_method: :post,
          path: BULK_CHECK_PATH,
          body: payload,
          timeout: timeout,
          retry_option: retry_option,
          headers: headers
        )

        base = base_result(response)

        BulkCheckResult.new(
          organizations: extract_organizations(envelope_data(response.body)),
          not_found_eins: extract_not_found_eins(base[:errors]),
          **base
        )
      end

      def inspect
        "#<#{self.class.name}>"
      end

      private

      # `retry` is a reserved word, so it arrives in the keyword splat rather than
      # as a named keyword. Anything else there is a typo worth hearing about.
      def request_retry(options)
        unknown = options.keys - [:retry]

        unless unknown.empty?
          raise ArgumentError,
                "unknown keyword#{"s" if unknown.size > 1}: #{unknown.map(&:inspect).join(", ")}"
        end

        options[:retry]
      end

      def bulk_payload(eins, dedupe)
        unless eins.is_a?(Array)
          raise ValidationError,
                "check_bulk expects an Array of EIN Strings, received #{eins.nil? ? "nil" : eins.class}."
        end

        raise ValidationError, "check_bulk requires at least one EIN." if eins.empty?

        # Validated and serialized from the same materialized list.
        normalized = EIN.normalize_all(eins.dup)
        payload = dedupe ? normalized.uniq : normalized

        if payload.size > MAX_BULK_EINS
          raise ValidationError,
                "check_bulk accepts at most #{MAX_BULK_EINS} EINs per request, received #{payload.size}. " \
                "Split the input into batches; this SDK does not chunk automatically."
        end

        payload
      end

      def base_result(response)
        envelope = ApiEnvelope.new(response.body.is_a?(Hash) ? response.body : {})

        {
          check_count: numeric(envelope.nonprofit_check_count),
          time_taken_ms: numeric(envelope.time_taken),
          errors: Transport.normalize_api_errors(envelope["errors"]),
          request_id: response.request_id,
          status: response.status,
          raw: response.body
        }
      end

      def numeric(value)
        value.is_a?(Numeric) ? value : nil
      end

      def envelope_data(body)
        body.is_a?(Hash) ? body["data"] : nil
      end

      def extract_nonprofit(data)
        record = data.is_a?(Array) ? data.first : data

        record.is_a?(Hash) ? Nonprofit.new(record) : nil
      end

      # The published schema returns `data` as an array. Some deployments wrap it
      # as `{ "organizations": [...] }`, so both are accepted rather than
      # silently yielding an empty list.
      def extract_organizations(data)
        list = data.is_a?(Hash) ? data["organizations"] : data

        list.is_a?(Array) ? list.grep(Hash).map { |record| Nonprofit.new(record) } : []
      end

      def extract_not_found_eins(errors)
        errors.flat_map do |detail|
          case detail.eins
          when Array then detail.eins.grep(String)
          when String then detail.eins.split(",").map(&:strip).reject(&:empty?)
          else []
          end
        end
      end
    end

    # Entry point for the SDK.
    #
    # Server-side use only. The API key is a private credential; do not use it
    # anywhere its value could reach an end user.
    #
    # @example
    #   client = Pactman::NonprofitCheckPlus::Client.new(api_key: ENV.fetch("PACTMAN_API_KEY"))
    class Client
      # @return [NonprofitsResource] nonprofit lookups.
      attr_reader :nonprofits

      # @param api_key [String] your Pactman API key. Load it from the environment
      #   or a secret manager; never commit it.
      # @param environment [Symbol, String, nil] named environment. Default `:production`.
      # @param base_url [String, nil] explicit base URL, for a mock server, a proxy,
      #   or a host Pactman has given you directly. Overrides `environment` when set.
      # @param timeout [Numeric, nil] timeout per attempt, in seconds. Default 30.
      # @param max_requests_per_second [Numeric, nil] optional client-side ceiling on
      #   outbound requests. Off by default; the server's limits are authoritative.
      # @param default_headers [Hash{String => String}, nil] extra headers sent with
      #   every request. Cannot override `Authorization`.
      # @param http_adapter [#call, nil] see {Http}. Default {Http::NetHttpAdapter}.
      # @param hooks [TransportHooks, nil] internal seam for injecting a clock in
      #   tests. Not covered by semantic versioning; do not depend on it.
      # @option options [false, Hash, RetryPolicy] :retry retry policy, or `false` to
      #   disable retrying entirely.
      # @raise [ConfigurationError] for unusable option values.
      # @raise [ArgumentError] for an option this client does not have.
      def initialize(api_key: nil, environment: nil, base_url: nil, timeout: nil, max_requests_per_second: nil,
                     default_headers: nil, http_adapter: nil, hooks: nil, **options)
        unknown = options.keys - [:retry]

        unless unknown.empty?
          raise ArgumentError,
                "unknown keyword#{"s" if unknown.size > 1}: #{unknown.map(&:inspect).join(", ")}. " \
                "Options are #{%i[api_key environment base_url timeout retry max_requests_per_second
                                  default_headers http_adapter].join(", ")}; timeouts and delays are in seconds."
        end

        api_key, @config = Config.resolve(
          api_key:, environment:, base_url:, timeout:, retry_option: options[:retry],
          max_requests_per_second:, default_headers:, http_adapter:
        )
        @nonprofits = NonprofitsResource.new(Transport.new(api_key, @config, hooks))
      end

      # @return [String] the resolved base URL every request is sent to.
      def base_url
        @config.base_url
      end

      # @return [Symbol, nil] the named environment in use, or `nil` when an
      #   explicit `base_url` was given.
      def environment
        @config.environment
      end

      # @return [Numeric] the resolved timeout, in seconds.
      def timeout
        @config.timeout
      end

      # @return [RetryPolicy] the resolved retry policy.
      def retry_policy
        @config.retry_policy
      end

      # A redacted view of the configuration.
      #
      # The API key is not an attribute of this object and never appears here,
      # in {#to_json}, {#inspect}, `pp`, `to_yaml`, or `Marshal`.
      #
      # @return [Hash{Symbol => Object}]
      def to_h
        {
          base_url: base_url,
          environment: environment,
          timeout: timeout,
          retry: retry_policy.to_h,
          max_requests_per_second: @config.max_requests_per_second,
          user_agent: @config.user_agent,
          api_key: "[redacted]"
        }
      end

      def to_json(*)
        to_h.to_json(*)
      end

      # `to_yaml` writes the redacted view too. Left to its default, Psych walks
      # instance variables — into the configuration, and from there into whatever
      # `http_adapter` the caller supplied, which this gem cannot vouch for.
      def encode_with(coder)
        coder.represent_map(nil, JSON.parse(to_json))
      end

      def inspect
        "#<#{self.class.name} base_url=#{base_url.inspect} environment=#{environment.inspect} " \
          "timeout=#{timeout} api_key=[redacted]>"
      end

      def to_s
        "#{self.class.name}(#{base_url})"
      end
    end
  end
end
