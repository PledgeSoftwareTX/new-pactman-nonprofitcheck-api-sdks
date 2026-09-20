# frozen_string_literal: true

require "json"
require "net/http"
require "time"
require "timeout"
require "uri"

# Pactman Nonprofit Check Plus SDK for Ruby.
#
# Server-side only — the API key is a private credential.
#
# @example
#   require "pactman/nonprofit_check_plus"
#
#   client = Pactman::NonprofitCheckPlus::Client.new(api_key: ENV.fetch("PACTMAN_API_KEY"))
#   nonprofit = client.nonprofits.check("41-1787097").nonprofit
module Pactman
  # Look up US nonprofits by EIN and read the IRS and OFAC findings behind the result.
  module NonprofitCheckPlus
  end
end

require_relative "nonprofit_check_plus/version"
require_relative "nonprofit_check_plus/errors"
require_relative "nonprofit_check_plus/environments"
require_relative "nonprofit_check_plus/ein"
require_relative "nonprofit_check_plus/models"
require_relative "nonprofit_check_plus/results"
require_relative "nonprofit_check_plus/sources"
require_relative "nonprofit_check_plus/config"
require_relative "nonprofit_check_plus/http"
require_relative "nonprofit_check_plus/transport"
require_relative "nonprofit_check_plus/client"
