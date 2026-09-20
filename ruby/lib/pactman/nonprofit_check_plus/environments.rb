# frozen_string_literal: true

module Pactman
  # Environments, endpoint paths and the batch limit.
  module NonprofitCheckPlus
    # Named Pactman environments that are supported for public SDK use.
    #
    # Endpoint hosts are declared in this file and nowhere else. Nothing in this
    # gem should contain a literal Pactman host.
    module Environment
      # The Pactman production API.
      PRODUCTION = :production
    end

    # Base URL for each named environment.
    #
    # Pactman's QA, SIT and sandbox hosts are internal and are deliberately not
    # exposed here. Point at one with the `base_url:` option if you have been
    # given access to it.
    BASE_URLS = {
      Environment::PRODUCTION => "https://entities.pactman.org"
    }.freeze
    private_constant :BASE_URLS

    # The environment used when none is supplied.
    DEFAULT_ENVIRONMENT = Environment::PRODUCTION

    # Path of the single-check endpoint. `{ein}` is replaced with a normalized EIN.
    SINGLE_CHECK_PATH = "/api/entities/nonprofitcheck/v1/us/ein/{ein}"

    # Path of the bulk-check endpoint.
    BULK_CHECK_PATH = "/api/entities/nonprofitcheckbulk/v1/us/eins"

    # Maximum number of EINs the API accepts in one bulk request.
    #
    # This mirrors the server-side limit. It is declared once, here.
    MAX_BULK_EINS = 50

    # Returns the base URL for a named environment.
    #
    # @param environment [Symbol, String]
    # @return [String]
    # @raise [ArgumentError] for an environment this gem does not know.
    def self.base_url_for_environment(environment)
      name = environment.respond_to?(:to_sym) ? environment.to_sym : environment

      BASE_URLS.fetch(name) do
        raise ArgumentError,
              "Unknown Pactman environment #{environment.inspect}. " \
              "Supported: #{supported_environments.join(", ")}."
      end
    end

    # Every environment name the SDK understands.
    #
    # @return [Array<Symbol>]
    def self.supported_environments
      BASE_URLS.keys
    end
  end
end
