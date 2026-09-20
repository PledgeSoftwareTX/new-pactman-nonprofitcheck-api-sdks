# frozen_string_literal: true

# Client bootstrap shared by the numbered examples.
#
# This is the pattern from `ex_01_secure_client_init.rb`, factored out so the
# other examples can stay on their own subject. Nothing here is part of the SDK.

require "pactman/nonprofit_check_plus"

module ExampleClient
  module_function

  # Reads the key from the environment, or exits with an explanation.
  #
  # The key is never printed, embedded in a message, or written to a file.
  def require_api_key
    api_key = ENV.fetch("PACTMAN_API_KEY", "")

    if api_key.empty?
      warn "Set PACTMAN_API_KEY before running this example."
      exit 1
    end

    api_key
  end

  # A reusable client, pointed at production unless `PACTMAN_BASE_URL` overrides
  # it. Build one per process and share it — each instance carries its own
  # throttle state.
  def create_client(**overrides)
    Pactman::NonprofitCheckPlus::Client.new(
      api_key: require_api_key,
      base_url: ENV.fetch("PACTMAN_BASE_URL", nil),
      timeout: 15,
      **overrides
    )
  end
end
