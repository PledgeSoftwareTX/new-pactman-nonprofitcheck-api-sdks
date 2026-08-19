from __future__ import annotations

import httpx
import pytest

from conftest import (
    BASE_URL,
    TEST_API_KEY,
    Clock,
    Stub,
    TransportMock,
    envelope,
    nonprofit_fixture,
)
from pactman_nonprofit_check_plus import (
    PactmanAuthenticationError,
    PactmanAuthorizationError,
    PactmanBadRequestError,
    PactmanClient,
    PactmanError,
    PactmanNotFoundError,
    PactmanRateLimitError,
    PactmanServerError,
    PactmanValidationError,
    RetryOptions,
)
from pactman_nonprofit_check_plus._http import compute_retry_delay, read_retry_after


def retrying_client(mock: TransportMock, clock: Clock, **options: object) -> PactmanClient:
    return PactmanClient(
        api_key=TEST_API_KEY,
        base_url=BASE_URL,
        http_client=mock.client(),
        _hooks=clock.hooks(),
        **options,  # type: ignore[arg-type]
    )


class TestAutomaticRetries:
    def test_succeeds_after_a_temporary_failure(self) -> None:
        mock = TransportMock(
            [Stub(status=503, body={}), Stub(body=envelope(nonprofit_fixture()))]
        )
        clock = Clock()
        result = retrying_client(mock, clock).nonprofits.check("411787097")

        assert len(mock.requests) == 2
        assert result.nonprofit is not None
        assert len(clock.delays) == 1

    def test_never_exceeds_the_configured_maximum_attempt_count(self) -> None:
        mock = TransportMock([Stub(status=503, body={})])
        clock = Clock()

        with pytest.raises(PactmanServerError) as excinfo:
            retrying_client(mock, clock, retry={"max_retries": 2}).nonprofits.check("411787097")

        assert len(mock.requests) == 3
        assert excinfo.value.attempts == 3

    def test_makes_a_single_attempt_when_retries_are_disabled(self) -> None:
        mock = TransportMock([Stub(status=503, body={})])
        clock = Clock()

        with pytest.raises(PactmanServerError):
            retrying_client(mock, clock, retry=False).nonprofits.check("411787097")

        assert len(mock.requests) == 1
        assert clock.delays == []

    def test_retries_temporary_network_failures(self) -> None:
        mock = TransportMock(
            [
                Stub(raises=httpx.ConnectError("connection reset")),
                Stub(body=envelope(nonprofit_fixture())),
            ]
        )
        clock = Clock()
        result = retrying_client(mock, clock).nonprofits.check("411787097")

        assert len(mock.requests) == 2
        assert result.nonprofit is not None

    def test_surfaces_a_401_as_an_authentication_error_on_the_first_attempt(self) -> None:
        mock = TransportMock([Stub(status=401, body={})])
        clock = Clock()

        with pytest.raises(PactmanAuthenticationError):
            retrying_client(mock, clock).nonprofits.check("411787097")

        assert len(mock.requests) == 1

    @pytest.mark.parametrize(
        ("status", "expected"),
        [
            (400, PactmanBadRequestError),
            (403, PactmanAuthorizationError),
            (404, PactmanNotFoundError),
        ],
    )
    def test_never_retries_a_status_that_cannot_succeed_on_a_repeat(
        self, status: int, expected: type[PactmanError]
    ) -> None:
        mock = TransportMock([Stub(status=status, body={})])
        clock = Clock()

        # Even when the caller explicitly lists the status as retryable.
        with pytest.raises(expected):
            retrying_client(
                mock, clock, retry={"retryable_statuses": (status,)}
            ).nonprofits.check("411787097")

        assert len(mock.requests) == 1

    def test_does_not_retry_local_validation_errors(self) -> None:
        mock = TransportMock([Stub(body=envelope(None))])
        clock = Clock()

        with pytest.raises(PactmanValidationError):
            retrying_client(mock, clock).nonprofits.check("nope")

        assert mock.requests == []

    def test_applies_exponential_backoff_with_a_deterministic_clock(self) -> None:
        mock = TransportMock([Stub(status=503, body={})])
        clock = Clock(random_value=1.0)

        with pytest.raises(PactmanServerError):
            retrying_client(
                mock,
                clock,
                retry={"max_retries": 3, "initial_delay": 0.5, "backoff_factor": 2.0},
            ).nonprofits.check("411787097")

        assert clock.delays == [0.5, 1.0, 2.0]

    def test_applies_full_jitter_across_the_backoff_window(self) -> None:
        mock = TransportMock([Stub(status=503, body={})])
        clock = Clock(random_value=0.25)

        with pytest.raises(PactmanServerError):
            retrying_client(
                mock, clock, retry={"max_retries": 2, "initial_delay": 1.0, "jitter": True}
            ).nonprofits.check("411787097")

        assert clock.delays == [0.25, 0.5]

    def test_caps_a_single_backoff_delay_at_max_delay(self) -> None:
        mock = TransportMock([Stub(status=503, body={})])
        clock = Clock(random_value=1.0)

        with pytest.raises(PactmanServerError):
            retrying_client(
                mock,
                clock,
                retry={"max_retries": 4, "initial_delay": 1.0, "max_delay": 2.0},
            ).nonprofits.check("411787097")

        assert clock.delays == [1.0, 2.0, 2.0, 2.0]

    def test_accepts_a_per_request_retry_override(self) -> None:
        mock = TransportMock([Stub(status=503, body={})])
        clock = Clock()

        with pytest.raises(PactmanServerError):
            retrying_client(mock, clock).nonprofits.check("411787097", retry=False)

        assert len(mock.requests) == 1

    def test_a_per_request_mapping_merges_onto_the_client_policy(self) -> None:
        mock = TransportMock([Stub(status=503, body={})])
        clock = Clock(random_value=1.0)
        client = retrying_client(mock, clock, retry={"initial_delay": 3.0, "jitter": False})

        with pytest.raises(PactmanServerError):
            client.nonprofits.check("411787097", retry={"max_retries": 1})

        # max_retries came from the override, initial_delay from the client.
        assert len(mock.requests) == 2
        assert clock.delays == [3.0]


class TestRateLimiting:
    def test_maps_429_to_the_rate_limit_error_and_exposes_retry_after(self) -> None:
        mock = TransportMock([Stub(status=429, headers={"retry-after": "30"}, body={})])
        clock = Clock()

        with pytest.raises(PactmanRateLimitError) as excinfo:
            retrying_client(mock, clock, retry=False).nonprofits.check("411787097")

        assert excinfo.value.retry_after_seconds == 30

    def test_waits_for_the_server_retry_after_before_falling_back_to_backoff(self) -> None:
        mock = TransportMock(
            [
                Stub(status=429, headers={"retry-after": "7"}, body={}),
                Stub(body=envelope(nonprofit_fixture())),
            ]
        )
        clock = Clock()
        retrying_client(mock, clock).nonprofits.check("411787097")

        assert clock.delays == [7.0]

    def test_ignores_retry_after_when_the_caller_opts_out(self) -> None:
        mock = TransportMock(
            [
                Stub(status=429, headers={"retry-after": "7"}, body={}),
                Stub(body=envelope(nonprofit_fixture())),
            ]
        )
        clock = Clock(random_value=1.0)
        retrying_client(
            mock, clock, retry={"respect_retry_after": False, "initial_delay": 0.5}
        ).nonprofits.check("411787097")

        assert clock.delays == [0.5]

    def test_reads_retry_after_given_as_an_http_date(self) -> None:
        headers = httpx.Headers({"retry-after": "Wed, 21 Oct 2026 07:28:00 GMT"})
        seconds = read_retry_after(headers, now=1792000000.0)

        assert seconds is not None
        assert seconds > 0

    @pytest.mark.parametrize("value", ["not-a-date", "", "   "])
    def test_ignores_an_unparseable_retry_after(self, value: str) -> None:
        assert read_retry_after(httpx.Headers({"retry-after": value})) is None

    def test_spaces_requests_when_a_client_side_limit_is_configured(self) -> None:
        mock = TransportMock([Stub(body=envelope(nonprofit_fixture()))])
        clock = Clock()
        client = retrying_client(mock, clock, max_requests_per_second=10)

        for _ in range(3):
            client.nonprofits.check("411787097")

        # The first request goes immediately; each later one waits out the interval.
        assert clock.delays == [0.1, 0.1]

    def test_does_not_throttle_when_no_client_side_limit_is_set(self) -> None:
        mock = TransportMock([Stub(body=envelope(nonprofit_fixture()))])
        clock = Clock()
        client = retrying_client(mock, clock)

        for _ in range(3):
            client.nonprofits.check("411787097")

        assert clock.delays == []


class TestComputeRetryDelay:
    def test_prefers_a_valid_retry_after_over_computed_backoff(self) -> None:
        assert compute_retry_delay(1, RetryOptions(), 9.0, lambda: 1.0) == 9.0

    def test_falls_back_to_backoff_when_retry_after_is_absent(self) -> None:
        policy = RetryOptions(initial_delay=0.5, backoff_factor=2.0, jitter=False)

        assert compute_retry_delay(1, policy, None) == 0.5
        assert compute_retry_delay(2, policy, None) == 1.0
        assert compute_retry_delay(3, policy, None) == 2.0

    def test_ignores_retry_after_when_the_policy_opts_out(self) -> None:
        policy = RetryOptions(respect_retry_after=False, initial_delay=0.25, jitter=False)

        assert compute_retry_delay(1, policy, 30.0) == 0.25
