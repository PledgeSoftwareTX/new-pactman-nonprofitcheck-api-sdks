"""
EX-24 — Timeout and request cancellation.

The timeout is always finite — 30 seconds by default, configurable per client or
per request, and impossible to disable.

Cancellation is Python's own: an asyncio task carrying an
:class:`AsyncPactmanClient` call is cancelled with ``task.cancel()``, and
``CancelledError`` propagates untouched. The SDK never converts it into a
:class:`PactmanError`, so "the caller went away" never looks like "the API
failed".

The two events stay different types::

    PactmanTimeoutError   the deadline you configured expired
    asyncio.CancelledError  you cancelled; nothing about the API is implied

Conflating them hides which side gave up. A timeout usually means raise the
budget or shed load; a cancellation means the caller went away.

Run:  PACTMAN_API_KEY=... python examples/ex_24_timeout_and_cancellation.py
"""

from __future__ import annotations

import asyncio
import os
import time

from lib.fixture_api import CONTROL_EINS, fixture_api
from lib.print import bullet, field, heading, note

from pactman_nonprofit_check_plus import (
    AsyncPactmanClient,
    PactmanNetworkError,
    PactmanTimeoutError,
)


def classify(error: BaseException) -> str:
    """One handler, two outcomes, no string matching."""
    if isinstance(error, PactmanTimeoutError):
        return f"timeout after {error.timeout}s — raise the budget or shed load"

    if isinstance(error, asyncio.CancelledError):
        return "cancelled — the caller stopped waiting; the API was never at fault"

    if isinstance(error, PactmanNetworkError):
        return "unreachable — nothing answered"

    return "something else entirely"


async def cancellation_demo(base_url: str) -> None:
    """Cancels an in-flight request, and shows CancelledError is not remapped."""
    heading("Caller cancellation with asyncio")

    async with AsyncPactmanClient(
        api_key=os.environ["PACTMAN_API_KEY"], base_url=base_url, timeout=10.0
    ) as client:
        started_at = time.monotonic()
        task = asyncio.create_task(client.nonprofits.check(CONTROL_EINS["slow"]))

        # Let the request get out the door, then stop caring about it.
        await asyncio.sleep(0.2)
        task.cancel()

        try:
            await task
            print("  Unexpectedly succeeded.")
        except asyncio.CancelledError as error:
            field("class", type(error).__name__)
            field("elapsed (ms)", round((time.monotonic() - started_at) * 1000))
            field("is a PactmanError", isinstance(error, PactmanTimeoutError))
            field("classified as", classify(error))

        # `asyncio.wait_for` bounds a whole operation, including any retries the
        # SDK still had planned. On 3.11+ `asyncio.timeout` reads better; this
        # form works on every version the SDK supports.
        heading("Bounding an operation with asyncio.wait_for")

        started_at = time.monotonic()

        try:
            await asyncio.wait_for(
                client.nonprofits.check(CONTROL_EINS["slow"], retry=False), timeout=0.3
            )

            print("  Unexpectedly succeeded.")
        except asyncio.TimeoutError:
            field("outcome", "wait_for cancelled the call at the deadline")
            field("elapsed (ms)", round((time.monotonic() - started_at) * 1000))


def main() -> int:
    with fixture_api() as client:
        base_url = client.base_url

        # The fixture endpoint holds the response open, so a short deadline expires.
        heading("A per-request timeout")

        started_at = time.monotonic()

        try:
            client.nonprofits.check(CONTROL_EINS["slow"], timeout=0.25, retry=False)
            print("  Unexpectedly succeeded.")
        except PactmanTimeoutError as error:
            field("class", type(error).__name__)
            field("category", error.category)
            field("origin", error.origin)
            field("timeout", error.timeout)
            field("attempts", error.attempts)
            field("elapsed (ms)", round((time.monotonic() - started_at) * 1000))
            field("classified as", classify(error))

        heading("A client-wide timeout")
        field("client default", f"{client.timeout}s")
        bullet("A per-request timeout overrides it for one call.")
        bullet("There is no value that disables either one.")

    asyncio.run(cancellation_demo(base_url))

    bullet("Cancelling before the call means no request is made at all.")
    bullet("Cancelling mid-flight ends the attempt and any retries still planned.")

    note(
        "There is no way to disable the timeout, by design. An unbounded request holds a\n"
        "connection, a worker, and a caller's patience for as long as the network lets it."
    )

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
