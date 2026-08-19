"""
EX-23 — Transient network or server failure.

Retries are on by default: two of them, exponential backoff from 0.5s with full
jitter, capped at 8 seconds per delay. Eligible are 429, 500, 502, 503, 504 and
connection failures that produced no response.

Never retried, whatever ``retryable_statuses`` contains: 400, 401, 403, 404, and
anything rejected by local validation. Retrying a rejected API key just burns the
same key three times; retrying a 404 cannot make a record exist.

Run:  PACTMAN_API_KEY=... python examples/ex_23_transient_retries.py
"""

from __future__ import annotations

import os
import time

from lib.fixture_api import CONTROL_EINS, FIXTURE_EINS, fixture_api
from lib.print import bullet, field, heading, note

from pactman_nonprofit_check_plus import (
    PactmanApiError,
    PactmanAuthenticationError,
    PactmanClient,
    PactmanNetworkError,
    PactmanNotFoundError,
    PactmanValidationError,
)


def main() -> int:
    with fixture_api() as client:
        base_url = client.base_url

        # The fixture endpoint answers 503 twice, then succeeds — a textbook
        # transient failure. Delays are shortened here so the example runs
        # quickly; the defaults are 0.5s initial and 8s maximum.
        heading("A 503 that clears on retry")

        started_at = time.monotonic()

        result = client.nonprofits.check(
            CONTROL_EINS["transient_failure"],
            retry={"max_retries": 3, "initial_delay": 0.04, "max_delay": 0.4},
        )

        name = result.nonprofit.get("organization_name") if result.nonprofit else None

        field("status", result.status)
        field("organization", name)
        field("elapsed (ms)", round((time.monotonic() - started_at) * 1000))
        bullet("Two 503s were absorbed; the caller saw one successful result.")
        bullet("Backoff grows exponentially and is jittered, so parallel clients scatter.")

        heading("The same failure with retries disabled")

        try:
            client.nonprofits.check(CONTROL_EINS["transient_failure"], retry=False)
            print("  Unexpectedly succeeded.")
        except PactmanApiError as error:
            field("class", type(error).__name__)
            field("status", error.status)
            field("attempts", error.attempts)
            field("api_message", error.api_message)

        heading("Failures that are never retried")

        # 404 — a definite answer. Retrying cannot change it.
        try:
            client.nonprofits.check(
                FIXTURE_EINS["no_record"],
                retry={"max_retries": 5, "retryable_statuses": (404, 500)},
            )
        except PactmanNotFoundError as error:
            field("404 attempts", f"{error.attempts} — not retried even though 404 was listed")

        # 401 — retrying a rejected credential achieves nothing.
        with PactmanClient(
            api_key="obviously-not-a-real-key",
            base_url=base_url,
            retry={"max_retries": 3},
        ) as bad_key_client:
            try:
                bad_key_client.nonprofits.check(FIXTURE_EINS["public_charity"])
            except PactmanAuthenticationError as error:
                field(
                    "401 attempts",
                    f"{error.attempts} — authentication failures are terminal",
                )

        # Local validation — nothing was sent, so there is nothing to retry.
        try:
            client.nonprofits.check("not-an-ein", retry={"max_retries": 3})
        except PactmanValidationError as error:
            field("validation", f"origin={error.origin} — rejected before any request")

        # A connection that never reaches a server: retried, then surfaced as a
        # network error carrying the attempt count.
        heading("A connection failure")

        with PactmanClient(
            api_key=os.environ.get("PACTMAN_API_KEY"),
            base_url="http://127.0.0.1:1",
            retry={"max_retries": 2, "initial_delay": 0.02, "max_delay": 0.06},
            timeout=2.0,
        ) as unreachable:
            try:
                unreachable.nonprofits.check(FIXTURE_EINS["public_charity"])
            except PactmanNetworkError as error:
                field("class", type(error).__name__)
                field("category", error.category)
                field("attempts", error.attempts)
                field("message", error.message)

    note(
        "A retried failure that eventually succeeds is a success. A retried failure that\n"
        'exhausts its budget is an outage — record it as "not checked", never as a pass.'
    )

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
