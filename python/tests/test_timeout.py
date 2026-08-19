from __future__ import annotations

import httpx
import pytest

from conftest import Clock, Stub, TransportMock, client_with, envelope, nonprofit_fixture
from pactman_nonprofit_check_plus import (
    DEFAULT_TIMEOUT,
    PactmanErrorCategory,
    PactmanTimeoutError,
)
from test_retry import retrying_client


class TestTimeouts:
    def test_documents_a_finite_default_timeout(self) -> None:
        assert DEFAULT_TIMEOUT == 30.0

    def test_applies_the_client_timeout_to_every_request(self) -> None:
        mock = TransportMock([Stub(body=envelope(nonprofit_fixture()))])
        client_with(mock, timeout=12.5).nonprofits.check("411787097")

        assert mock.requests[0].extensions["timeout"]["read"] == 12.5

    def test_lets_a_per_request_timeout_override_the_client_default(self) -> None:
        mock = TransportMock([Stub(body=envelope(nonprofit_fixture()))])
        client_with(mock, timeout=30).nonprofits.check("411787097", timeout=1.5)

        assert mock.requests[0].extensions["timeout"]["read"] == 1.5

    def test_produces_a_timeout_error_when_the_endpoint_exceeds_the_configured_timeout(
        self,
    ) -> None:
        mock = TransportMock([Stub(raises=httpx.ReadTimeout("too slow"))])

        with pytest.raises(PactmanTimeoutError) as excinfo:
            client_with(mock, timeout=0.25, retry=False).nonprofits.check("411787097")

        error = excinfo.value
        assert error.category is PactmanErrorCategory.TIMEOUT
        assert error.timeout == 0.25
        assert error.attempts == 1
        assert "0.25s" in error.message

    def test_distinguishes_a_timeout_from_a_generic_transport_failure(self) -> None:
        mock = TransportMock([Stub(raises=httpx.ConnectTimeout("no route"))])

        with pytest.raises(PactmanTimeoutError):
            client_with(mock, retry=False).nonprofits.check("411787097")

    def test_retries_a_timeout_when_the_retry_policy_allows_it(self) -> None:
        mock = TransportMock(
            [
                Stub(raises=httpx.ReadTimeout("too slow")),
                Stub(body=envelope(nonprofit_fixture())),
            ]
        )
        clock = Clock()
        result = retrying_client(mock, clock).nonprofits.check("411787097")

        assert len(mock.requests) == 2
        assert result.nonprofit is not None

    def test_reports_the_attempt_count_on_a_timeout_that_exhausted_its_retries(self) -> None:
        mock = TransportMock([Stub(raises=httpx.ReadTimeout("too slow"))])
        clock = Clock()

        with pytest.raises(PactmanTimeoutError) as excinfo:
            retrying_client(mock, clock, retry={"max_retries": 2}).nonprofits.check("411787097")

        assert excinfo.value.attempts == 3
        assert len(mock.requests) == 3

    def test_chains_the_underlying_transport_exception_as_the_cause(self) -> None:
        mock = TransportMock([Stub(raises=httpx.ReadTimeout("too slow"))])

        with pytest.raises(PactmanTimeoutError) as excinfo:
            client_with(mock, retry=False).nonprofits.check("411787097")

        assert isinstance(excinfo.value.__cause__, httpx.ReadTimeout)
