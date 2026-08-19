"""Shared fixtures and doubles for the test suite."""

from __future__ import annotations

import json
from dataclasses import dataclass, field
from typing import Any

import httpx

from pactman_nonprofit_check_plus import AsyncPactmanClient, PactmanClient
from pactman_nonprofit_check_plus._http import TransportHooks

TEST_API_KEY = "pactman_test_key_do_not_leak_8f2b"
"""A key that must never appear in any diagnostic output."""

BASE_URL = "http://mock.test"

_UNSET = object()


@dataclass
class Stub:
    """A canned HTTP response, or an error the transport should see raised."""

    status: int = 200
    body: Any = _UNSET
    body_text: str | None = None
    headers: dict[str, str] = field(default_factory=dict)
    raises: BaseException | None = None


class TransportMock:
    """
    Serves ``stubs`` in order; the last one repeats once the queue is exhausted
    so a retry test can end on a stable outcome.
    """

    def __init__(self, stubs: list[Stub]) -> None:
        if not stubs:
            raise ValueError("TransportMock was created with an empty stub list.")

        self._stubs = stubs
        self._index = 0
        self.requests: list[httpx.Request] = []

    def _handle(self, request: httpx.Request) -> httpx.Response:
        request.read()
        self.requests.append(request)

        stub = self._stubs[min(self._index, len(self._stubs) - 1)]
        self._index += 1

        if stub.raises is not None:
            raise stub.raises

        headers = {"content-type": "application/json", **stub.headers}

        if stub.body_text is not None:
            content = stub.body_text
        elif stub.body is _UNSET:
            content = ""
        else:
            content = json.dumps(stub.body)

        return httpx.Response(stub.status, headers=headers, content=content)

    @property
    def transport(self) -> httpx.MockTransport:
        return httpx.MockTransport(self._handle)

    def client(self) -> httpx.Client:
        return httpx.Client(transport=self.transport)

    def async_client(self) -> httpx.AsyncClient:
        return httpx.AsyncClient(transport=self.transport)

    def json_body(self, index: int = 0) -> Any:
        """The JSON payload of a recorded request."""
        return json.loads(self.requests[index].content)


class Clock:
    """Records requested delays instead of waiting, so retry tests stay instant."""

    def __init__(self, random_value: float = 1.0) -> None:
        self.delays: list[float] = []
        self.random_value = random_value
        self._now = 0.0

    def _sleep(self, seconds: float) -> None:
        self.delays.append(seconds)
        self._now += seconds

    async def _async_sleep(self, seconds: float) -> None:
        self.delays.append(seconds)
        self._now += seconds

    def hooks(self) -> TransportHooks:
        return TransportHooks(
            sleep=self._sleep,
            random=lambda: self.random_value,
            monotonic=lambda: self._now,
        )

    def async_hooks(self) -> TransportHooks:
        return TransportHooks(
            sleep=self._async_sleep,
            random=lambda: self.random_value,
            monotonic=lambda: self._now,
        )


def client_with(mock: TransportMock, **options: Any) -> PactmanClient:
    """A client wired to ``mock``, using the documented mock-server setup."""
    return PactmanClient(
        api_key=TEST_API_KEY, base_url=BASE_URL, http_client=mock.client(), **options
    )


def async_client_with(mock: TransportMock, **options: Any) -> AsyncPactmanClient:
    return AsyncPactmanClient(
        api_key=TEST_API_KEY, base_url=BASE_URL, http_client=mock.async_client(), **options
    )


def nonprofit_fixture(**overrides: Any) -> dict[str, Any]:
    """A representative organization, mirroring the published response example."""
    return {
        "pactman_org_url": "https://pactman.org/profile/nonprofit/example-nonprofit-r5U9r8yRcZ",
        "organization_info_last_modified": "2/22/2026 1:16:30 AM",
        "ein": "411787097",
        "organization_name": "EXAMPLE NONPROFIT",
        "organization_name_aka": "EXAMPLE N.P",
        "address_line1": "50 LOWELL AVE",
        "address_line2": "APT 3B",
        "city": "WESTFIELD",
        "state": "MA",
        "state_name": "Massachusetts",
        "zip": "01085-2643",
        "filing_req_code": "00",
        "pub78_church_message": None,
        "pub78_organization_name": "Example Nonprofit",
        "pub78_ein": "411787097",
        "pub78_verified": True,
        "pub78_city": "Westfield",
        "pub78_state": "MA",
        "pub78_indicator": "0",
        "organization_types": [
            {
                "organization_type": "Deductions for donations to public charities are generally limited...",
                "deductibility_limitation": "50%",
                "deductibility_status_description": "PC",
            }
        ],
        "most_recent_pub78": "12/12/2025 12:00:00 AM",
        "bmf_church_message": None,
        "bmf_organization_name": "EXAMPLE NONPROFIT",
        "bmf_ein": "411787097",
        "bmf_status": True,
        "most_recent_bmf": "12/09/2025 12:00:00 AM",
        "bmf_subsection": "03",
        "subsection_description": "501(c)(3) Public Charity",
        "foundation_code": "10",
        "foundation_code_description": "Public charity described in section 509(a)(1) or (2)",
        "ruling_month": "07",
        "ruling_year": "2024",
        "group_exemption": "0000",
        "exempt_status_code": "01",
        "ofac_status": (
            "This organization was NOT included in the Office of Foreign Assets "
            "Control Specially Designated Nationals (SDN) list."
        ),
        "revocation_code": None,
        "revocation_date": None,
        "reinstatement_date": None,
        "irs_bmf_pub78_conflict": False,
        "foundation_509a_status": "N/A",
        "report_date": "3/25/2026 3:28:54 PM",
        "foundation_type_code": "pc",
        "foundation_type_description": "Public charity described in section 509(a)(1) or (2)",
        **overrides,
    }


def envelope(data: Any, **overrides: Any) -> dict[str, Any]:
    """Wraps data in the envelope the API returns."""
    return {
        "code": 200,
        "message": "OK",
        "errors": None,
        "data": data,
        "timeTaken": 3,
        "nonprofit_check_count": 1,
        **overrides,
    }
