"""
EX-22 — Rate-limit response and Retry-After.

HTTP 429 becomes :class:`PactmanRateLimitError`, carrying the status, the
server's ``Retry-After`` when it sent one, and sanitized request metadata.

Three behaviours are shown: surfacing the error with retries off, letting the
bounded retry policy honour ``Retry-After``, and reducing pressure with a
client-side ceiling plus a bounded worker pool.

Run:  PACTMAN_API_KEY=... python examples/ex_22_rate_limit.py
"""

from __future__ import annotations

import json
import os
import time
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timedelta, timezone

from lib.client import require_api_key
from lib.fixture_api import CONTROL_EINS, FIXTURE_EINS, fixture_api
from lib.print import bullet, field, heading, note

from pactman_nonprofit_check_plus import PactmanClient, PactmanRateLimitError


def main() -> int:
    api_key = os.environ.get("PACTMAN_API_KEY", "")

    with fixture_api() as client:
        base_url = client.base_url

        # 1. Retries off, so the 429 reaches the caller untouched.
        heading("Surfacing the error")

        try:
            client.nonprofits.check(CONTROL_EINS["rate_limited"], retry=False)
            print("  Unexpectedly succeeded.")
        except PactmanRateLimitError as error:
            field("class", type(error).__name__)
            field("category", error.category)
            field("status", error.status)
            field("retry_after_seconds", error.retry_after_seconds)
            field("request_id", error.request_id)
            field("attempts", error.attempts)
            field("api_message", error.api_message)

            for detail in error.api_errors:
                bullet(f"{detail.get('resource')}: {detail.get('reason')}")

            # Safe to log wholesale — no credential reaches any of these fields.
            serialized = json.dumps(error.to_dict(), default=str)
            field("to_dict() contains the key", bool(api_key) and api_key in serialized)

            # Schedule your own backoff from the server's number when you handle
            # 429s yourself. Fall back to your own delay when it is absent.
            wait = error.retry_after_seconds if error.retry_after_seconds is not None else 5
            retry_at = datetime.now(timezone.utc) + timedelta(seconds=wait)
            field("would retry at", retry_at.isoformat())

        # 2. Bounded automatic retry. 429 is retryable and `Retry-After` wins over
        #    computed backoff, so the SDK waits exactly as long as it was told to.
        heading("Bounded automatic retry")

        started_at = time.monotonic()

        try:
            client.nonprofits.check(
                CONTROL_EINS["rate_limited"],
                retry={"max_retries": 1, "respect_retry_after": True},
            )
            print("  Unexpectedly succeeded.")
        except PactmanRateLimitError as error:
            field("class", type(error).__name__)
            field("attempts", error.attempts)
            field("elapsed (ms)", round((time.monotonic() - started_at) * 1000))
            bullet("The retry honoured Retry-After, then gave up at the configured bound.")
            bullet("Retries stay finite; the SDK never retries indefinitely.")

        # 3. Reduce pressure rather than absorb rejections: cap outbound rate and
        #    keep your own concurrency small. Prefer one bulk call to many single
        #    ones.
        heading("Reducing pressure")

        eins = [
            FIXTURE_EINS["public_charity"],
            FIXTURE_EINS["public_charity_second"],
            FIXTURE_EINS["private_foundation"],
            FIXTURE_EINS["reinstated"],
        ]

        with PactmanClient(
            api_key=require_api_key(),
            base_url=base_url,
            max_requests_per_second=3,
            retry={"max_retries": 2},
        ) as paced:
            begin = time.monotonic()

            def lookup(ein: str) -> str:
                nonprofit = paced.nonprofits.check(ein).nonprofit

                return str(nonprofit.get("organization_name")) if nonprofit else "no record"

            # The SDK throttles outbound requests; it does not queue for you.
            with ThreadPoolExecutor(max_workers=2) as pool:
                names = list(pool.map(lookup, eins))

            field("max_requests_per_second", 3)
            field("concurrency limit", 2)
            field("requests", len(names))
            field("elapsed (ms)", round((time.monotonic() - begin) * 1000))

            for name in names:
                bullet(name)

    note(
        "The server's limits are authoritative and can change per account and endpoint.\n"
        "Treat max_requests_per_second as a courtesy throttle, not a guarantee, and prefer\n"
        "the bulk endpoint over a fan-out of single checks."
    )

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
