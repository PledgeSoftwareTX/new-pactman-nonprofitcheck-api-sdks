"""
Concurrent checks with the async client.

Run:  PACTMAN_API_KEY=... python examples/async_concurrent.py

`check_bulk` is the right tool for a known list of EINs — one request instead of
many. Use this pattern when the lookups are genuinely independent, for example
when each one belongs to a different tenant or needs its own error handling.
"""

from __future__ import annotations

import asyncio
import os
import sys

from pactman_nonprofit_check_plus import AsyncPactmanClient, PactmanError

EINS = ["41-1787097", "996589560", "999999999"]


async def main() -> int:
    api_key = os.environ.get("PACTMAN_API_KEY")

    if not api_key:
        print("Set PACTMAN_API_KEY before running this example.", file=sys.stderr)
        return 1

    async with AsyncPactmanClient(
        api_key=api_key,
        base_url=os.environ.get("PACTMAN_BASE_URL"),
        # A client-side ceiling keeps a burst of concurrent calls civil. The
        # server's limits remain authoritative.
        max_requests_per_second=5,
    ) as client:
        results = await asyncio.gather(
            *(client.nonprofits.check(ein) for ein in EINS),
            return_exceptions=True,
        )

    for ein, outcome in zip(EINS, results, strict=True):
        if isinstance(outcome, PactmanError):
            print(f"{ein}: failed — {outcome}")
        elif isinstance(outcome, BaseException):
            raise outcome
        elif outcome.nonprofit is None:
            print(f"{ein}: no record")
        else:
            print(f"{ein}: {outcome.nonprofit['organization_name']}")

    return 0


if __name__ == "__main__":
    raise SystemExit(asyncio.run(main()))
