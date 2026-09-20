# frozen_string_literal: true

module Pactman
  module NonprofitCheckPlus
    # The result of {NonprofitsResource#check}.
    #
    # @!attribute [r] nonprofit
    #   @return [Nonprofit, nil] the organization, or `nil` when the API returned no record.
    # @!attribute [r] check_count
    #   `nonprofit_check_count` from the envelope: checks consumed so far in the
    #   current billing cycle, including this request, resetting each cycle.
    #
    #   Not the size of this request. Take the delta between two responses if you
    #   need that, and read this one as a usage gauge.
    #   @return [Numeric, nil]
    # @!attribute [r] time_taken_ms
    #   @return [Numeric, nil] server-side processing time in milliseconds, when reported.
    # @!attribute [r] errors
    #   Item-level failures reported alongside a successful response. Empty when
    #   the API reported none.
    #   @return [Array<ApiErrorDetail>]
    # @!attribute [r] request_id
    #   @return [String, nil] correlation identifier from the response headers.
    # @!attribute [r] status
    #   @return [Integer] HTTP status of the response.
    # @!attribute [r] raw
    #   The unmodified parsed response body, including any fields not declared on
    #   the models. {#nonprofit} reads from inside it rather than from a copy.
    #   @return [Hash, String, nil]
    SingleCheckResult = Data.define(:nonprofit, :check_count, :time_taken_ms, :errors, :request_id, :status, :raw)

    # The result of {NonprofitsResource#check_bulk}.
    #
    # Carries every attribute {SingleCheckResult} does except `nonprofit`, and:
    #
    # @!attribute [r] organizations
    #   Organizations the API matched, in the order it returned them — which is
    #   not guaranteed to follow the order you supplied. Index by `ein`.
    #   @return [Array<Nonprofit>]
    # @!attribute [r] not_found_eins
    #   EINs the API reported no record for, collected from `errors`.
    #
    #   A bulk request where some EINs miss is a successful HTTP 200, not an error.
    #   @return [Array<String>]
    BulkCheckResult = Data.define(
      :organizations, :not_found_eins, :check_count, :time_taken_ms, :errors, :request_id, :status, :raw
    )
  end
end
