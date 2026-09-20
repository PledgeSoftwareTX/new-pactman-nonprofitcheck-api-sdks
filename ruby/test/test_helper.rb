# frozen_string_literal: true

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))

require "pactman/nonprofit_check_plus"
require "minitest/autorun"

# Shared doubles and fixtures. Nothing here is part of the gem.
module TestSupport
  NCP = Pactman::NonprofitCheckPlus

  BASE_URL = "http://mock.test"

  # A key that must never appear in any diagnostic output.
  TEST_API_KEY = "pactman_test_key_do_not_leak_8f2b"

  # Serves `stubs` in order; the last one repeats once the queue is exhausted so
  # a retry test can end on a stable outcome.
  #
  # A stub is a Hash (`status:`, `body:`, `body_text:`, `headers:`), an
  # exception to raise, or a callable that receives the request and returns
  # either of those.
  class FakeAdapter
    attr_reader :requests

    def initialize(stubs)
      raise ArgumentError, "FakeAdapter needs at least one stub." if stubs.empty?

      @stubs = stubs
      @requests = []
    end

    def call(request)
      @requests << request

      stub = @stubs[[@requests.size - 1, @stubs.size - 1].min]
      stub = stub.call(request) if stub.respond_to?(:call)

      raise stub if stub.is_a?(Exception)

      headers = { "content-type" => "application/json" }.merge(stub.fetch(:headers, {}))
      text = stub[:body_text] || (stub.key?(:body) ? JSON.generate(stub[:body]) : "")

      NCP::Http::Response.new(status: stub.fetch(:status, 200), headers: headers, body: text)
    end
  end

  # Records requested delays instead of waiting, so retry tests stay instant.
  #
  # With `advance: true` a sleep moves the fake clock forward, as a real one
  # would; without it, time stands still and throttle waits accumulate.
  class FakeClock
    attr_reader :delays

    def initialize(random: 1.0, advance: true)
      @random = random
      @advance = advance
      @now = 1_000.0
      @delays = []
    end

    def hooks
      NCP::TransportHooks.new(
        sleep: lambda do |seconds|
          @delays << seconds
          @now += seconds if @advance
        end,
        random: -> { @random },
        monotonic: -> { @now }
      )
    end
  end

  module_function

  # A representative organization, mirroring the published response example.
  def nonprofit_fixture(overrides = {})
    {
      "pactman_org_url" => "https://pactman.org/profile/nonprofit/example-nonprofit-r5U9r8yRcZ",
      "organization_info_last_modified" => "2/22/2026 1:16:30 AM",
      "ein" => "411787097",
      "organization_name" => "EXAMPLE NONPROFIT",
      "organization_name_aka" => "EXAMPLE N.P",
      "address_line1" => "50 LOWELL AVE",
      "address_line2" => "APT 3B",
      "city" => "WESTFIELD",
      "state" => "MA",
      "state_name" => "Massachusetts",
      "zip" => "01085-2643",
      "filing_req_code" => "00",
      "pub78_church_message" => nil,
      "pub78_organization_name" => "Example Nonprofit",
      "pub78_ein" => "411787097",
      "pub78_verified" => true,
      "pub78_city" => "Westfield",
      "pub78_state" => "MA",
      "pub78_indicator" => "0",
      "organization_types" => [
        {
          "organization_type" => "Deductions for donations to public charities are generally limited...",
          "deductibility_limitation" => "50%",
          "deductibility_status_description" => "PC"
        }
      ],
      "most_recent_pub78" => "12/12/2025 12:00:00 AM",
      "bmf_church_message" => nil,
      "bmf_organization_name" => "EXAMPLE NONPROFIT",
      "bmf_ein" => "411787097",
      "bmf_status" => true,
      "most_recent_bmf" => "12/09/2025 12:00:00 AM",
      "bmf_subsection" => "03",
      "subsection_description" => "501(c)(3) Public Charity",
      "foundation_code" => "10",
      "foundation_code_description" => "Public charity described in section 509(a)(1) or (2)",
      "ruling_month" => "07",
      "ruling_year" => "2024",
      "group_exemption" => "0000",
      "exempt_status_code" => "01",
      "ofac_status" => "This organization was NOT included in the Office of Foreign Assets Control " \
                       "Specially Designated Nationals (SDN) list.",
      "revocation_code" => nil,
      "revocation_date" => nil,
      "reinstatement_date" => nil,
      "irs_bmf_pub78_conflict" => false,
      "foundation_509a_status" => "N/A",
      "report_date" => "3/25/2026 3:28:54 PM",
      "foundation_type_code" => "pc",
      "foundation_type_description" => "Public charity described in section 509(a)(1) or (2)"
    }.merge(overrides)
  end

  # Wraps data in the envelope the API returns.
  def envelope(data, overrides = {})
    {
      "code" => 200,
      "message" => "OK",
      "errors" => nil,
      "data" => data,
      "timeTaken" => 3,
      "nonprofit_check_count" => 1
    }.merge(overrides)
  end

  # A client over a fake adapter, with retries' waits recorded rather than slept.
  def client_with(adapter, clock: FakeClock.new, **)
    NCP::Client.new(api_key: TEST_API_KEY, base_url: BASE_URL, http_adapter: adapter, hooks: clock.hooks, **)
  end
end
