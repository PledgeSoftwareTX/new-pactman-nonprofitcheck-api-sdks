from __future__ import annotations

import httpx
import pytest

from conftest import TEST_API_KEY, Stub, TransportMock, client_with, envelope
from pactman_nonprofit_check_plus import (
    PactmanApiError,
    PactmanAuthenticationError,
    PactmanAuthorizationError,
    PactmanBadRequestError,
    PactmanError,
    PactmanErrorCategory,
    PactmanErrorOrigin,
    PactmanNetworkError,
    PactmanNotFoundError,
    PactmanRateLimitError,
    PactmanServerError,
    PactmanTimeoutError,
    PactmanValidationError,
    is_pactman_error,
)


class TestStatusToErrorCategoryMapping:
    @pytest.mark.parametrize(
        ("status", "expected", "category"),
        [
            (400, PactmanBadRequestError, PactmanErrorCategory.BAD_REQUEST),
            (401, PactmanAuthenticationError, PactmanErrorCategory.AUTHENTICATION),
            (403, PactmanAuthorizationError, PactmanErrorCategory.AUTHORIZATION),
            (404, PactmanNotFoundError, PactmanErrorCategory.NOT_FOUND),
            (429, PactmanRateLimitError, PactmanErrorCategory.RATE_LIMIT),
            (500, PactmanServerError, PactmanErrorCategory.SERVER),
            (503, PactmanServerError, PactmanErrorCategory.SERVER),
        ],
    )
    def test_maps_each_status_to_its_error_type(
        self, status: int, expected: type[PactmanApiError], category: PactmanErrorCategory
    ) -> None:
        mock = TransportMock([Stub(status=status, body={"code": status, "message": "nope"})])

        with pytest.raises(expected) as excinfo:
            client_with(mock, retry=False).nonprofits.check("411787097")

        assert excinfo.value.category is category
        assert excinfo.value.status == status

    def test_falls_back_to_a_general_api_error_for_an_unexpected_status(self) -> None:
        mock = TransportMock([Stub(status=418, body={"message": "teapot"})])

        with pytest.raises(PactmanApiError) as excinfo:
            client_with(mock, retry=False).nonprofits.check("411787097")

        assert type(excinfo.value) is PactmanApiError
        assert excinfo.value.category is PactmanErrorCategory.API
        assert excinfo.value.status == 418

    def test_keeps_response_metadata_when_the_body_cannot_be_deserialized(self) -> None:
        mock = TransportMock(
            [
                Stub(
                    status=500,
                    body_text="<html>gateway exploded</html>",
                    headers={"content-type": "text/html", "x-request-id": "req-42"},
                )
            ]
        )

        with pytest.raises(PactmanServerError) as excinfo:
            client_with(mock, retry=False).nonprofits.check("411787097")

        error = excinfo.value
        assert error.status == 500
        assert error.request_id == "req-42"
        assert error.raw == "<html>gateway exploded</html>"
        assert "gateway exploded" in (error.api_message or "")


class TestErrorDetail:
    def test_exposes_retry_after_on_a_429(self) -> None:
        mock = TransportMock([Stub(status=429, headers={"retry-after": "12"}, body={})])

        with pytest.raises(PactmanRateLimitError) as excinfo:
            client_with(mock, retry=False).nonprofits.check("411787097")

        assert excinfo.value.retry_after_seconds == 12

    def test_retains_the_request_id_on_a_server_error(self) -> None:
        mock = TransportMock([Stub(status=502, headers={"x-correlation-id": "corr-7"}, body={})])

        with pytest.raises(PactmanServerError) as excinfo:
            client_with(mock, retry=False).nonprofits.check("411787097")

        assert excinfo.value.request_id == "corr-7"

    def test_surfaces_the_api_reason_list_without_string_parsing(self) -> None:
        mock = TransportMock(
            [
                Stub(
                    status=400,
                    body={
                        "code": 400,
                        "errors": [
                            {"resource": "nonprofitcheck", "reason": "EIN is malformed", "code": 400},
                            {"resource": "nonprofitcheck", "reason": "EIN is required", "code": 400},
                        ],
                    },
                )
            ]
        )

        with pytest.raises(PactmanBadRequestError) as excinfo:
            client_with(mock, retry=False).nonprofits.check("411787097")

        error = excinfo.value
        assert [detail["reason"] for detail in error.api_errors] == [
            "EIN is malformed",
            "EIN is required",
        ]
        assert error.api_code == 400
        assert error.message == "EIN is malformed; EIN is required"

    def test_reports_transport_failures_as_network_errors(self) -> None:
        mock = TransportMock([Stub(raises=httpx.ConnectError("connection refused"))])

        with pytest.raises(PactmanNetworkError) as excinfo:
            client_with(mock, retry=False).nonprofits.check("411787097")

        assert excinfo.value.category is PactmanErrorCategory.NETWORK
        assert excinfo.value.attempts == 1
        assert isinstance(excinfo.value.__cause__, httpx.ConnectError)

    def test_distinguishes_local_errors_from_api_errors(self) -> None:
        mock = TransportMock([Stub(status=400, body={"message": "rejected"})])

        with pytest.raises(PactmanValidationError) as local:
            client_with(mock).nonprofits.check("nope")

        with pytest.raises(PactmanBadRequestError) as remote:
            client_with(mock, retry=False).nonprofits.check("411787097")

        assert local.value.origin is PactmanErrorOrigin.LOCAL
        assert remote.value.origin is PactmanErrorOrigin.API

    def test_is_catchable_through_the_common_base_class(self) -> None:
        mock = TransportMock([Stub(status=401, body={})])

        with pytest.raises(PactmanError) as excinfo:
            client_with(mock, retry=False).nonprofits.check("411787097")

        assert is_pactman_error(excinfo.value)

    def test_serializes_without_the_raw_body_or_the_credential(self) -> None:
        mock = TransportMock([Stub(status=401, body={"message": "bad key"})])

        with pytest.raises(PactmanAuthenticationError) as excinfo:
            client_with(mock, retry=False).nonprofits.check("411787097")

        payload = excinfo.value.to_dict()
        assert payload["status"] == 401
        assert payload["category"] == "authentication"
        assert payload["origin"] == "api"
        assert "raw" not in payload


class TestCredentialSafetyInDiagnostics:
    def test_keeps_the_api_key_out_of_an_api_error(self) -> None:
        mock = TransportMock([Stub(status=401, body={"message": "unauthorized"})])

        with pytest.raises(PactmanAuthenticationError) as excinfo:
            client_with(mock, retry=False).nonprofits.check("411787097")

        error = excinfo.value
        assert TEST_API_KEY not in str(error)
        assert TEST_API_KEY not in repr(error)
        assert TEST_API_KEY not in str(error.to_dict())

    def test_keeps_the_api_key_out_of_a_network_error(self) -> None:
        mock = TransportMock([Stub(raises=httpx.ConnectError("connection refused"))])

        with pytest.raises(PactmanNetworkError) as excinfo:
            client_with(mock, retry=False).nonprofits.check("411787097")

        assert TEST_API_KEY not in str(excinfo.value)

    def test_keeps_the_api_key_out_of_a_timeout_error(self) -> None:
        mock = TransportMock([Stub(raises=httpx.ReadTimeout("timed out"))])

        with pytest.raises(PactmanTimeoutError) as excinfo:
            client_with(mock, retry=False).nonprofits.check("411787097")

        assert TEST_API_KEY not in str(excinfo.value)
        assert TEST_API_KEY not in str(excinfo.value.to_dict())

    def test_keeps_the_api_key_out_of_a_successful_result(self) -> None:
        mock = TransportMock([Stub(body=envelope(None))])
        result = client_with(mock).nonprofits.check("411787097")

        assert TEST_API_KEY not in repr(result)
