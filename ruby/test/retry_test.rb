# frozen_string_literal: true

require_relative "test_helper"

class RetryTest < Minitest::Test
  include TestSupport

  def build(stubs, random: 1.0, advance: true, **)
    adapter = FakeAdapter.new(stubs)
    clock = FakeClock.new(random: random, advance: advance)

    [adapter, clock, client_with(adapter, clock: clock, **)]
  end

  def test_succeeds_after_a_temporary_failure
    adapter, _clock, client = build([{ status: 503, body: { "code" => 503 } }, { body: envelope(nonprofit_fixture) }])

    result = client.nonprofits.check("411787097")

    assert_equal 2, adapter.requests.size
    assert_equal "411787097", result.nonprofit.ein
  end

  def test_never_exceeds_the_configured_maximum_attempt_count
    adapter, _clock, client = build([{ status: 500, body: { "code" => 500 } }],
                                    retry: { max_retries: 3, jitter: false })

    error = assert_raises(NCP::ServerError) { client.nonprofits.check("411787097") }

    assert_equal 4, adapter.requests.size
    assert_equal 4, error.attempts
  end

  def test_makes_a_single_attempt_when_retries_are_disabled
    adapter, _clock, client = build([{ status: 500, body: { "code" => 500 } }], retry: false)

    assert_raises(NCP::ServerError) { client.nonprofits.check("411787097") }
    assert_equal 1, adapter.requests.size
  end

  def test_retries_temporary_network_failures
    adapter, _clock, client = build([Errno::ECONNRESET.new, { body: envelope(nonprofit_fixture) }])

    client.nonprofits.check("411787097")

    assert_equal 2, adapter.requests.size
  end

  def test_does_not_retry_authentication_authorization_validation_or_not_found
    [401, 403, 400, 404].each do |status|
      adapter, _clock, client = build([{ status: status, body: { "code" => status } }],
                                      retry: { retryable_statuses: [400, 401, 403, 404, 500] })

      assert_raises(NCP::ApiError) { client.nonprofits.check("411787097") }
      assert_equal 1, adapter.requests.size, "HTTP #{status} was retried"
    end
  end

  def test_surfaces_a_401_as_an_authentication_error_on_the_first_attempt
    _adapter, _clock, client = build([{ status: 401, body: { "code" => 401 } }])

    error = assert_raises(NCP::AuthenticationError) { client.nonprofits.check("411787097") }

    assert_equal 1, error.attempts
  end

  def test_does_not_retry_local_validation_errors
    adapter, _clock, client = build([{ body: envelope(nonprofit_fixture) }])

    assert_raises(NCP::ValidationError) { client.nonprofits.check("bad") }
    assert_empty adapter.requests
  end

  def test_applies_exponential_backoff_with_a_deterministic_clock
    _adapter, clock, client = build([{ status: 500, body: {} }],
                                    retry: { max_retries: 3, jitter: false, initial_delay: 0.1, backoff_factor: 2 })

    assert_raises(NCP::ServerError) { client.nonprofits.check("411787097") }
    assert_equal [0.1, 0.2, 0.4], clock.delays
  end

  def test_applies_full_jitter_across_the_backoff_window
    _adapter, clock, client = build([{ status: 500, body: {} }],
                                    random: 0.5, retry: { max_retries: 2, jitter: true, initial_delay: 0.1 })

    assert_raises(NCP::ServerError) { client.nonprofits.check("411787097") }
    assert_equal [0.05, 0.1], clock.delays
  end

  def test_caps_a_single_backoff_delay_at_max_delay
    _adapter, clock, client = build([{ status: 500, body: {} }],
                                    retry: { max_retries: 3, jitter: false, initial_delay: 1, backoff_factor: 10,
                                             max_delay: 2 })

    assert_raises(NCP::ServerError) { client.nonprofits.check("411787097") }
    assert_equal [1.0, 2.0, 2.0], clock.delays
  end

  def test_accepts_a_per_request_retry_override
    adapter, _clock, client = build([{ status: 500, body: {} }], retry: false)

    assert_raises(NCP::ServerError) { client.nonprofits.check("411787097", retry: { max_retries: 1 }) }
    assert_equal 2, adapter.requests.size
  end

  def test_accepts_a_per_request_opt_out
    adapter, _clock, client = build([{ status: 500, body: {} }])

    assert_raises(NCP::ServerError) { client.nonprofits.check_bulk(["411787097"], retry: false) }
    assert_equal 1, adapter.requests.size
  end

  def test_rejects_a_malformed_per_request_retry_before_sending
    adapter, _clock, client = build([{ body: envelope(nonprofit_fixture) }])

    assert_raises(NCP::ConfigurationError) { client.nonprofits.check("411787097", retry: { max_retries: -1 }) }
    assert_empty adapter.requests
  end
end

class RateLimitTest < Minitest::Test
  include TestSupport

  def test_maps_429_to_the_rate_limit_error_and_exposes_retry_after
    adapter = FakeAdapter.new([{ status: 429, body: { "code" => 429 }, headers: { "retry-after" => "5" } }])

    error = assert_raises(NCP::RateLimitError) { client_with(adapter, retry: false).nonprofits.check("411787097") }

    assert_equal 5, error.retry_after_seconds
  end

  def test_waits_for_the_server_retry_after_before_falling_back_to_backoff
    adapter = FakeAdapter.new([{ status: 429, body: {}, headers: { "retry-after" => "7" } },
                               { body: envelope(nonprofit_fixture) }])
    clock = FakeClock.new

    client_with(adapter, clock: clock, retry: { jitter: false, initial_delay: 0.1 }).nonprofits.check("411787097")

    assert_equal [7.0], clock.delays
  end

  def test_ignores_retry_after_when_the_caller_opts_out
    adapter = FakeAdapter.new([{ status: 429, body: {}, headers: { "retry-after" => "7" } },
                               { body: envelope(nonprofit_fixture) }])
    clock = FakeClock.new

    client_with(adapter, clock: clock, retry: { jitter: false, initial_delay: 0.25, respect_retry_after: false })
      .nonprofits.check("411787097")

    assert_equal [0.25], clock.delays
  end

  def test_reads_retry_after_given_as_an_http_date
    now = Time.utc(2026, 1, 1, 12, 0, 0)
    headers = { "retry-after" => (now + 4).httpdate }
    policy = NCP::RetryPolicy.new(jitter: false)

    assert_in_delta 4, NCP::Transport.read_retry_after(headers, now)
    assert_in_delta 4.0, NCP::Transport.compute_retry_delay(1, policy, 4, -> { 1 })
  end

  def test_treats_a_retry_after_date_in_the_past_as_zero
    now = Time.utc(2026, 1, 1, 12, 0, 0)

    assert_equal 0, NCP::Transport.read_retry_after({ "retry-after" => (now - 30).httpdate }, now)
  end

  def test_ignores_an_unparseable_or_negative_retry_after
    assert_nil NCP::Transport.read_retry_after({ "retry-after" => "soon" })
    assert_nil NCP::Transport.read_retry_after({ "retry-after" => "-5" })
    assert_nil NCP::Transport.read_retry_after({ "retry-after" => "  " })
    assert_nil NCP::Transport.read_retry_after({})
  end

  def test_spaces_requests_when_a_client_side_limit_is_configured
    adapter = FakeAdapter.new([{ body: envelope(nonprofit_fixture) }])
    clock = FakeClock.new
    client = client_with(adapter, clock: clock, max_requests_per_second: 2)

    3.times { client.nonprofits.check("411787097") }

    # Two requests per second is a half-second slot each. The first goes out at
    # once; each after it waits for the slot the previous one reserved.
    assert_equal [0.5, 0.5], clock.delays
  end

  def test_accumulates_the_schedule_for_a_burst
    adapter = FakeAdapter.new([{ body: envelope(nonprofit_fixture) }])
    clock = FakeClock.new(advance: false)
    client = client_with(adapter, clock: clock, max_requests_per_second: 2)

    3.times { client.nonprofits.check("411787097") }

    # Time stands still, so the third request queues behind the second.
    assert_equal [0.5, 1.0], clock.delays
  end

  def test_shares_one_schedule_across_threads
    adapter = FakeAdapter.new([{ body: envelope(nonprofit_fixture) }])
    clock = FakeClock.new(advance: false)
    client = client_with(adapter, clock: clock, max_requests_per_second: 4)

    Array.new(4) { Thread.new { client.nonprofits.check("411787097") } }.each(&:join)

    assert_equal [0.25, 0.5, 0.75], clock.delays.sort
  end

  def test_does_not_throttle_when_no_client_side_limit_is_set
    adapter = FakeAdapter.new([{ body: envelope(nonprofit_fixture) }])
    clock = FakeClock.new
    client = client_with(adapter, clock: clock)

    2.times { client.nonprofits.check("411787097") }

    assert_empty clock.delays
  end
end

class ComputeRetryDelayTest < Minitest::Test
  include TestSupport

  def test_prefers_a_valid_retry_after_over_computed_backoff
    assert_in_delta 3.0, NCP::Transport.compute_retry_delay(1, NCP::RetryPolicy.new(jitter: false), 3)
  end

  def test_falls_back_to_backoff_when_retry_after_is_absent
    policy = NCP::RetryPolicy.new(jitter: false)

    assert_in_delta 0.5, NCP::Transport.compute_retry_delay(1, policy, nil)
    assert_in_delta 2.0, NCP::Transport.compute_retry_delay(3, policy, nil)
  end
end
