# frozen_string_literal: true

module Pactman
  module NonprofitCheckPlus
    # Default timeout per attempt, in seconds.
    DEFAULT_TIMEOUT = 30

    # Retry policy. Applied per request, on top of the overall timeout.
    #
    # Every attribute has the SDK default, so `RetryPolicy.new(max_retries: 5)` is
    # a complete policy rather than a patch. To adjust a client's policy for one
    # request without restating it, pass a Hash as that call's `retry:` — its keys
    # are merged onto the policy in force.
    #
    # @!attribute [r] max_retries
    #   Retries after the first attempt. `0` disables retrying. Default `2`
    #   (three attempts in total).
    #   @return [Integer]
    # @!attribute [r] initial_delay
    #   Delay before the first retry, in seconds. Subsequent delays grow by
    #   `backoff_factor` and are randomized when `jitter` is on. Default `0.5`.
    #   @return [Numeric]
    # @!attribute [r] max_delay
    #   Ceiling for a single backoff delay, in seconds. A server-supplied
    #   `Retry-After` is honored even when it exceeds this. Default `8`.
    #   @return [Numeric]
    # @!attribute [r] backoff_factor
    #   @return [Numeric] default `2`.
    # @!attribute [r] jitter
    #   Randomize each delay across `[0, computed]` (full jitter) so that clients
    #   failing together do not retry in lockstep. Default `true`.
    #   @return [Boolean]
    # @!attribute [r] retryable_statuses
    #   HTTP statuses worth retrying. Authentication, authorization, validation
    #   and not-found responses are never retried, whatever this contains.
    #   Default `[429, 500, 502, 503, 504]`.
    #   @return [Array<Integer>]
    # @!attribute [r] respect_retry_after
    #   Wait for the server's `Retry-After` before falling back to backoff.
    #   Default `true`.
    #   @return [Boolean]
    RetryPolicy = Data.define(
      :max_retries, :initial_delay, :max_delay, :backoff_factor, :jitter, :retryable_statuses, :respect_retry_after
    ) do
      def initialize(max_retries: 2, initial_delay: 0.5, max_delay: 8, backoff_factor: 2, jitter: true,
                     retryable_statuses: [429, 500, 502, 503, 504], respect_retry_after: true)
        unless max_retries.is_a?(Integer) && max_retries >= 0
          raise ConfigurationError, "`retry.max_retries` must be an integer of 0 or more."
        end

        raise ConfigurationError, "`retry.initial_delay` must be 0 or more." unless Config.non_negative?(initial_delay)
        raise ConfigurationError, "`retry.max_delay` must be 0 or more." unless Config.non_negative?(max_delay)

        unless Config.finite_number?(backoff_factor) && backoff_factor >= 1
          raise ConfigurationError, "`retry.backoff_factor` must be 1 or more."
        end

        raise ConfigurationError, "`retry.jitter` must be true or false." unless [true, false].include?(jitter)

        unless [true, false].include?(respect_retry_after)
          raise ConfigurationError, "`retry.respect_retry_after` must be true or false."
        end

        unless retryable_statuses.is_a?(Array) && retryable_statuses.all?(Integer)
          raise ConfigurationError, "`retry.retryable_statuses` must be an Array of integer HTTP statuses."
        end

        # A copy, frozen, so a caller's array cannot mutate a live client's policy.
        super(max_retries:, initial_delay:, max_delay:, backoff_factor:, jitter:,
              retryable_statuses: retryable_statuses.dup.freeze, respect_retry_after:)
      end

      # True when `status` may be retried under this policy.
      #
      # @param status [Integer]
      # @return [Boolean]
      def retryable_status?(status)
        return false if Config::NEVER_RETRY_STATUSES.include?(status)

        retryable_statuses.include?(status)
      end
    end

    # Fully-resolved configuration. The API key is not part of it.
    #
    # @api private
    ResolvedConfig = Data.define(
      :base_url, :environment, :timeout, :retry_policy, :max_requests_per_second, :default_headers, :user_agent,
      :http_adapter
    )

    # Client configuration: defaults, validation, and resolution.
    #
    # @api private
    module Config
      # Statuses that are never retried, regardless of `retryable_statuses`.
      NEVER_RETRY_STATUSES = [400, 401, 403, 404].freeze

      class << self
        # Validates and resolves client options.
        #
        # @return [Array(String, ResolvedConfig)] the API key, held apart from the rest.
        # @raise [ConfigurationError] for a missing or blank API key, an unknown
        #   environment, a malformed base URL, or nonsensical numeric options.
        def resolve(api_key:, environment:, base_url:, timeout:, retry_option:, max_requests_per_second:,
                    default_headers:, http_adapter:)
          key = validate_api_key(api_key)

          config = ResolvedConfig.new(
            base_url: base_url.nil? ? base_url_for(environment) : validate_base_url(base_url),
            environment: base_url.nil? ? (environment || DEFAULT_ENVIRONMENT).to_sym : nil,
            timeout: timeout.nil? ? DEFAULT_TIMEOUT : validate_timeout(timeout),
            retry_policy: resolve_retry(RetryPolicy.new, retry_option),
            max_requests_per_second: validate_requests_per_second(max_requests_per_second),
            default_headers: validate_headers(default_headers, "default_headers"),
            user_agent: user_agent,
            http_adapter: validate_adapter(http_adapter)
          )

          [key, config]
        end

        # Applies a `retry:` argument to the policy currently in force.
        #
        # `nil` keeps it, `false` disables retrying, `true` keeps it, a
        # {RetryPolicy} replaces it outright, and a Hash merges its keys onto it.
        def resolve_retry(current, override)
          case override
          when nil, true then current
          when false then current.with(max_retries: 0)
          when RetryPolicy then override
          when Hash then merge_retry(current, override)
          else
            raise ConfigurationError,
                  "`retry` must be false, a Hash of policy options, or a RetryPolicy, received #{override.class}."
          end
        end

        # @return [Numeric]
        def validate_timeout(timeout)
          return timeout if finite_number?(timeout) && timeout.positive?

          raise ConfigurationError,
                "`timeout` must be a finite number of seconds greater than zero. " \
                "There is no way to disable the timeout."
        end

        # @return [Hash{String => String}]
        def validate_headers(headers, option)
          return {}.freeze if headers.nil?

          raise ConfigurationError, "`#{option}` must be a Hash of header names to values." unless headers.is_a?(Hash)

          headers.to_h do |name, value|
            unless (name.is_a?(String) || name.is_a?(Symbol)) && value.is_a?(String)
              raise ConfigurationError, "`#{option}` must map String header names to String values."
            end

            if name.to_s.match?(/[\r\n]/) || value.match?(/[\r\n]/)
              raise ConfigurationError, "`#{option}` contains a line break, which HTTP headers cannot carry."
            end

            [name.to_s, value]
          end.freeze
        end

        # `pactman-nonprofit-check-plus/<version> (ruby/<version>; <platform>)`
        def user_agent
          "#{GEM_NAME}/#{VERSION} (ruby/#{RUBY_VERSION}; #{RUBY_PLATFORM})"
        end

        def finite_number?(value)
          (value.is_a?(Integer) || value.is_a?(Float) || value.is_a?(Rational)) && value.finite?
        end

        def non_negative?(value)
          finite_number?(value) && value >= 0
        end

        private

        def merge_retry(current, overrides)
          known = RetryPolicy.members
          unknown = overrides.keys.reject { |name| known.include?(name.to_s.to_sym) }

          unless unknown.empty?
            raise ConfigurationError,
                  "Unknown retry option #{unknown.map(&:inspect).join(", ")}. Known: #{known.join(", ")}."
          end

          current.with(**overrides.transform_keys { |name| name.to_s.to_sym })
        end

        def validate_api_key(api_key)
          if api_key.nil?
            raise ConfigurationError,
                  'A Pactman API key is required. Pass `api_key:`, for example ENV.fetch("PACTMAN_API_KEY").'
          end

          unless api_key.is_a?(String)
            raise ConfigurationError, "The Pactman API key must be a String, received #{api_key.class}."
          end

          if api_key.strip.empty?
            raise ConfigurationError,
                  "The Pactman API key is empty. Check that the environment variable holding it is set."
          end

          api_key.strip
        end

        def base_url_for(environment)
          name = environment || DEFAULT_ENVIRONMENT
          supported = NonprofitCheckPlus.supported_environments

          unless name.respond_to?(:to_sym) && supported.include?(name.to_sym)
            raise ConfigurationError,
                  "Unknown environment #{name.inspect}. Supported: #{supported.join(", ")}. " \
                  "Use `base_url:` to target a host that is not a named environment."
          end

          NonprofitCheckPlus.base_url_for_environment(name)
        end

        def validate_base_url(base_url)
          if !base_url.is_a?(String) || base_url.strip.empty?
            raise ConfigurationError, "`base_url` must be a non-empty URL String."
          end

          uri = parse_url(base_url)

          unless %w[http https].include?(uri.scheme&.downcase)
            raise ConfigurationError,
                  "`base_url` must use http or https, received #{uri.scheme}:."
          end

          origin(uri) + uri.path.sub(%r{/+\z}, "")
        end

        def parse_url(base_url)
          uri = URI.parse(base_url.strip)

          # A bare host such as `entities.pactman.org` parses as a relative path,
          # with no scheme and no host. It is not a URL anything can be sent to.
          raise URI::InvalidURIError if uri.scheme.nil? || uri.host.to_s.empty?

          uri
        rescue URI::InvalidURIError
          raise ConfigurationError,
                "`base_url` is not a valid URL: #{base_url.inspect}. Expected something like https://entities.pactman.org."
        end

        def origin(uri)
          scheme = uri.scheme.downcase
          port = uri.port == uri.default_port ? "" : ":#{uri.port}"

          "#{scheme}://#{uri.host.downcase}#{port}"
        end

        def validate_requests_per_second(value)
          return nil if value.nil?
          return value if finite_number?(value) && value.positive?

          raise ConfigurationError, "`max_requests_per_second` must be a finite number greater than zero, or nil."
        end

        def validate_adapter(adapter)
          return Http::NetHttpAdapter.new if adapter.nil?
          return adapter if adapter.respond_to?(:call)

          raise ConfigurationError, "`http_adapter` must respond to #call(request)."
        end
      end
    end
  end
end
