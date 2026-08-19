"""
Parity checks for the async client.

The sync suites cover the shared request-building and response-shaping code.
These cover what only the async path can get wrong: awaiting, cancellation, and
connection-pool lifecycle.
"""

from __future__ import annotations

import asyncio

import httpx
import pytest

from conftest import (
    BASE_URL,
    TEST_API_KEY,
    Clock,
    Stub,
    TransportMock,
    async_client_with,
    envelope,
    nonprofit_fixture,
)
from pactman_nonprofit_check_plus import (
    AsyncPactmanClient,
    PactmanServerError,
    PactmanTimeoutError,
    PactmanValidationError,
)


async def test_check_returns_the_same_shape_as_the_sync_client() -> None:
    mock = TransportMock([Stub(body=envelope(nonprofit_fixture()))])
    client = async_client_with(mock)
    result = await client.nonprofits.check("41-1787097")

    assert str(mock.requests[0].url).endswith("/us/ein/411787097")
    assert mock.requests[0].headers["authorization"] == f"Bearer {TEST_API_KEY}"
    assert result.nonprofit is not None
    assert result.nonprofit["organization_name"] == "EXAMPLE NONPROFIT"
    assert result.check_count == 1

    await client.aclose()


async def test_check_bulk_sends_a_normalized_array() -> None:
    mock = TransportMock([Stub(body=envelope([nonprofit_fixture()]))])
    client = async_client_with(mock)
    result = await client.nonprofits.check_bulk(["41-1787097", "996589560"])

    assert mock.json_body() == ["411787097", "996589560"]
    assert len(result.organizations) == 1

    await client.aclose()


async def test_validates_locally_before_awaiting_anything() -> None:
    mock = TransportMock([Stub(body=envelope(None))])
    client = async_client_with(mock)

    with pytest.raises(PactmanValidationError):
        await client.nonprofits.check("41178709")

    assert mock.requests == []

    await client.aclose()


async def test_retries_with_the_injected_clock() -> None:
    mock = TransportMock(
        [Stub(status=503, body={}), Stub(body=envelope(nonprofit_fixture()))]
    )
    clock = Clock(random_value=1.0)
    client = AsyncPactmanClient(
        api_key=TEST_API_KEY,
        base_url=BASE_URL,
        http_client=mock.async_client(),
        retry={"initial_delay": 0.5},
        _hooks=clock.async_hooks(),
    )

    result = await client.nonprofits.check("411787097")

    assert len(mock.requests) == 2
    assert clock.delays == [0.5]
    assert result.nonprofit is not None

    await client.aclose()


async def test_exhausts_retries_and_raises_the_api_error() -> None:
    mock = TransportMock([Stub(status=503, body={})])
    clock = Clock()
    client = AsyncPactmanClient(
        api_key=TEST_API_KEY,
        base_url=BASE_URL,
        http_client=mock.async_client(),
        retry={"max_retries": 1},
        _hooks=clock.async_hooks(),
    )

    with pytest.raises(PactmanServerError) as excinfo:
        await client.nonprofits.check("411787097")

    assert excinfo.value.attempts == 2
    assert len(mock.requests) == 2

    await client.aclose()


async def test_maps_a_transport_timeout() -> None:
    mock = TransportMock([Stub(raises=httpx.ReadTimeout("too slow"))])
    client = async_client_with(mock, timeout=0.25, retry=False)

    with pytest.raises(PactmanTimeoutError) as excinfo:
        await client.nonprofits.check("411787097")

    assert excinfo.value.timeout == 0.25

    await client.aclose()


async def test_cancelling_the_task_does_not_become_a_pactman_error() -> None:
    started = asyncio.Event()

    async def handler(request: httpx.Request) -> httpx.Response:
        started.set()
        await asyncio.sleep(10)
        return httpx.Response(200, json=envelope(None))

    transport = httpx.MockTransport(handler)
    client = AsyncPactmanClient(
        api_key=TEST_API_KEY,
        base_url=BASE_URL,
        http_client=httpx.AsyncClient(transport=transport),
    )

    task = asyncio.create_task(client.nonprofits.check("411787097"))
    await started.wait()
    task.cancel()

    with pytest.raises(asyncio.CancelledError):
        await task

    await client.aclose()


async def test_context_manager_closes_a_client_it_created() -> None:
    async with AsyncPactmanClient(api_key=TEST_API_KEY) as client:
        underlying = client._client
        assert not underlying.is_closed

    assert underlying.is_closed


async def test_context_manager_leaves_a_supplied_client_open() -> None:
    mock = TransportMock([Stub(body=envelope(None))])
    supplied = mock.async_client()

    async with AsyncPactmanClient(
        api_key=TEST_API_KEY, base_url=BASE_URL, http_client=supplied
    ) as client:
        await client.nonprofits.check("411787097")

    assert not supplied.is_closed

    await supplied.aclose()


def test_sync_context_manager_closes_a_client_it_created() -> None:
    from pactman_nonprofit_check_plus import PactmanClient

    with PactmanClient(api_key=TEST_API_KEY) as client:
        underlying = client._client
        assert not underlying.is_closed

    assert underlying.is_closed
