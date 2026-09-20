# frozen_string_literal: true

module Pactman
  module NonprofitCheckPlus
    # Stable, machine-comparable error categories.
    #
    # Every error this gem raises carries one, so callers can branch on the class
    # or on the category without parsing message strings.
    module ErrorCategory
      # The client was constructed with unusable options.
      CONFIGURATION = :configuration
      # Input failed the SDK's local validation; no request was sent.
      VALIDATION = :validation
      # HTTP 401. The API key is missing, malformed, revoked or unrecognized.
      AUTHENTICATION = :authentication
      # HTTP 403. The key is valid but lacks access to the resource.
      AUTHORIZATION = :authorization
      # HTTP 400. The API rejected the request.
      BAD_REQUEST = :bad_request
      # HTTP 404. No matching record.
      NOT_FOUND = :not_found
      # HTTP 429. Rate limit exceeded.
      RATE_LIMIT = :rate_limit
      # HTTP 5xx.
      SERVER = :server
      # The request exceeded the configured timeout.
      TIMEOUT = :timeout
      # The request never produced an HTTP response.
      NETWORK = :network
      # An API error that does not fall into a more specific category.
      API = :api

      # @return [Array<Symbol>] every category, in declaration order.
      def self.all
        constants.map { |name| const_get(name) }
      end
    end

    # Whether an error was raised locally or derived from an API response.
    module ErrorOrigin
      LOCAL = :local
      API = :api
    end

    # Base class for every error this gem raises.
    #
    # API keys are never placed into an error message, an error attribute, or
    # the output of {#to_h}.
    class Error < StandardError
      # @return [Symbol] one of {ErrorCategory}.
      attr_reader :category

      # @return [Symbol] one of {ErrorOrigin}.
      attr_reader :origin

      def initialize(message = nil, category:, origin:)
        super(message)
        @category = category
        @origin = origin
      end

      # A sanitized view, safe to log or attach to a support ticket.
      #
      # @return [Hash{Symbol => Object}]
      def to_h
        { name: self.class.name, message: message, category: category, origin: origin }
      end

      def to_json(*)
        to_h.to_json(*)
      end
    end

    # The client options were unusable — a missing API key, a malformed base URL.
    class ConfigurationError < Error
      def initialize(message = nil)
        super(message, category: ErrorCategory::CONFIGURATION, origin: ErrorOrigin::LOCAL)
      end
    end

    # One item that failed local validation.
    #
    # @!attribute [r] message
    #   @return [String] human-readable reason the value was rejected.
    # @!attribute [r] index
    #   @return [Integer, nil] position in the input collection, for bulk calls.
    # @!attribute [r] value
    #   @return [Object] the offending value, as supplied by the caller.
    ValidationIssue = Data.define(:message, :index, :value)

    # Input failed local validation. No HTTP request was sent.
    #
    # Distinguishable from an API-side 400 by `origin == :local`.
    class ValidationError < Error
      # @return [Array<ValidationIssue>]
      attr_reader :issues

      def initialize(message = nil, issues = [])
        super(message, category: ErrorCategory::VALIDATION, origin: ErrorOrigin::LOCAL)
        @issues = issues.freeze
      end

      def to_h
        super.merge(issues: issues.map(&:to_h))
      end
    end

    # An error returned by the Pactman API.
    #
    # Raised directly when the status maps to no more specific subclass. Response
    # metadata is preserved even when the body could not be deserialized.
    class ApiError < Error
      # @return [Integer] HTTP status code.
      attr_reader :status
      # @return [String, nil] `message` from the response envelope, or the reasons it listed.
      attr_reader :api_message
      # @return [Numeric, nil] `code` from the response envelope.
      attr_reader :api_code
      # @return [Array<ApiErrorDetail>] `errors` from the response envelope, as a list.
      attr_reader :api_errors
      # @return [String, nil] correlation identifier from the response headers.
      attr_reader :request_id
      # @return [Numeric, nil] `Retry-After` in seconds, when the server sent a valid one.
      attr_reader :retry_after_seconds
      # @return [Hash, String, nil] the parsed response body, or the raw text when it was not JSON.
      attr_reader :raw
      # @return [Integer] how many attempts were made before this error was raised.
      attr_reader :attempts

      # @return [Symbol] the category every instance of this class carries.
      def self.category
        ErrorCategory::API
      end

      def initialize(message = nil, status:, api_message: nil, api_code: nil, api_errors: [],
                     request_id: nil, retry_after_seconds: nil, raw: nil, attempts: 1)
        super(message, category: self.class.category, origin: ErrorOrigin::API)
        @status = status
        @api_message = api_message
        @api_code = api_code
        @api_errors = api_errors.freeze
        @request_id = request_id
        @retry_after_seconds = retry_after_seconds
        @raw = raw
        @attempts = attempts
      end

      def to_h
        super.merge(
          status: status,
          api_message: api_message,
          api_code: api_code,
          api_errors: api_errors.map(&:to_h),
          request_id: request_id,
          retry_after_seconds: retry_after_seconds,
          attempts: attempts
        )
      end

      # Builds the subclass that matches an HTTP status code.
      #
      # @api private
      def self.for_status(status:, **init)
        message = init[:api_message].to_s.strip
        message = default_message_for(status) if message.empty?

        error_class_for(status).new(message, status: status, **init)
      end

      def self.error_class_for(status)
        case status
        when 400 then BadRequestError
        when 401 then AuthenticationError
        when 403 then AuthorizationError
        when 404 then NotFoundError
        when 429 then RateLimitError
        else status >= 500 ? ServerError : ApiError
        end
      end
      private_class_method :error_class_for

      def self.default_message_for(status)
        case status
        when 400 then "The Pactman API rejected the request."
        when 401 then "The Pactman API key was rejected."
        when 403 then "This Pactman API key is not permitted to access that resource."
        when 404 then "No matching record was found."
        when 429 then "The Pactman API rate limit was exceeded."
        else
          if status >= 500
            "The Pactman API returned a server error (HTTP #{status})."
          else
            "The Pactman API returned an unexpected response (HTTP #{status})."
          end
        end
      end
      private_class_method :default_message_for
    end

    # HTTP 401.
    class AuthenticationError < ApiError
      def self.category
        ErrorCategory::AUTHENTICATION
      end
    end

    # HTTP 403.
    class AuthorizationError < ApiError
      def self.category
        ErrorCategory::AUTHORIZATION
      end
    end

    # HTTP 400. The API rejected the request; see `api_errors` for the reasons.
    class BadRequestError < ApiError
      def self.category
        ErrorCategory::BAD_REQUEST
      end
    end

    # HTTP 404.
    class NotFoundError < ApiError
      def self.category
        ErrorCategory::NOT_FOUND
      end
    end

    # HTTP 429. `retry_after_seconds` carries the server's `Retry-After` when sent.
    class RateLimitError < ApiError
      def self.category
        ErrorCategory::RATE_LIMIT
      end
    end

    # HTTP 5xx.
    class ServerError < ApiError
      def self.category
        ErrorCategory::SERVER
      end
    end

    # The request exceeded the configured timeout.
    class TimeoutError < Error
      # @return [Numeric] the timeout that expired, in seconds.
      attr_reader :timeout
      # @return [Integer]
      attr_reader :attempts

      def initialize(message = nil, timeout:, attempts: 1)
        super(message, category: ErrorCategory::TIMEOUT, origin: ErrorOrigin::LOCAL)
        @timeout = timeout
        @attempts = attempts
      end

      def to_h
        super.merge(timeout: timeout, attempts: attempts)
      end
    end

    # The request produced no HTTP response: a refused connection, a reset, a
    # failed TLS handshake, a DNS miss.
    #
    # Caller cancellation is not one of these. A `Thread#kill`, a
    # `Timeout.timeout` or a fiber scheduler stopping the call propagates as
    # itself — see the README's "Timeouts and cancellation".
    class NetworkError < Error
      # @return [Integer]
      attr_reader :attempts

      def initialize(message = nil, attempts: 1)
        super(message, category: ErrorCategory::NETWORK, origin: ErrorOrigin::LOCAL)
        @attempts = attempts
      end

      def to_h
        super.merge(attempts: attempts)
      end
    end
  end
end
