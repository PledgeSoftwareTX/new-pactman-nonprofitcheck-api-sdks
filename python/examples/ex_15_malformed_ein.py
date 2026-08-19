"""
EX-15 — Malformed EIN rejected locally.

Bad input never becomes a request. Every rejection below happens in-process, so
it costs no quota, no latency, and no rate-limit budget.

The example counts outbound HTTP calls with an instrumented transport to prove
the claim rather than assert it.

Run:  PACTMAN_API_KEY=... python examples/ex_15_malformed_ein.py
"""

from __future__ import annotations

import contextlib
import json
import os
from typing import Any

import httpx
from lib.client import require_api_key
from lib.print import bullet, field, heading, note

from pactman_nonprofit_check_plus import (
    EIN_LENGTH,
    PactmanClient,
    PactmanValidationError,
    is_valid_ein,
)

BAD_SINGLE_INPUTS: list[tuple[str, Any]] = [
    ("too few digits", "41178709"),
    ("too many digits", "4117870977"),
    ("letters", "41-178709A"),
    ("empty string", ""),
    ("whitespace only", "   "),
    ("None", None),
    ("a number, not a string", 411787097),
    ("a list, not a string", ["411787097"]),
    ("unsupported punctuation", "41.1787097"),
    ("hyphen in the wrong place", "411-787097"),
    ("two hyphens", "41-178-7097"),
]

BAD_BATCHES: list[tuple[str, Any]] = [
    ("one bad entry", ["411787097", "nope", "996589560"]),
    ("several bad entries", ["1234", "411787097", "", None]),
    ("not a list", "not-a-list"),
    ("empty list", []),
]


class CountingTransport(httpx.BaseTransport):
    """Wraps a real transport. If any call below reaches the network, this moves."""

    def __init__(self, inner: httpx.BaseTransport) -> None:
        self._inner = inner
        self.requests_sent = 0

    def handle_request(self, request: httpx.Request) -> httpx.Response:
        self.requests_sent += 1

        return self._inner.handle_request(request)

    def close(self) -> None:
        self._inner.close()


def main() -> int:
    base_url = os.environ.get("PACTMAN_BASE_URL")
    transport = CountingTransport(httpx.HTTPTransport())

    client = PactmanClient(
        api_key=require_api_key(),
        base_url=base_url,
        http_client=httpx.Client(transport=transport),
    )

    heading(
        f"Single checks (EINs are {EIN_LENGTH} digits, optionally hyphenated XX-XXXXXXX)"
    )

    for label, value in BAD_SINGLE_INPUTS:
        try:
            client.nonprofits.check(value)
            print(f"  {label.ljust(26)} UNEXPECTEDLY ACCEPTED")
        except PactmanValidationError as error:
            # `issues` identifies the offending value, so a form can highlight
            # the field rather than showing a generic failure.
            issue = error.issues[0] if error.issues else None
            valid = str(is_valid_ein(value)).ljust(6)

            print(
                f"  {label.ljust(26)} is_valid_ein={valid}"
                f" origin={error.origin}  {issue.message if issue else error.message}"
            )

    heading("Bulk checks — every failure is reported at once, by index")

    for label, batch in BAD_BATCHES:
        try:
            client.nonprofits.check_bulk(batch)
            print(f"  {label}: UNEXPECTEDLY ACCEPTED")
        except PactmanValidationError as error:
            print(f"\n  {label}: {error.message}")

            for issue in error.issues:
                bullet(f"index {issue.index}: {json.dumps(issue.value)} — {issue.message}")

    # One valid call, to show the counter is wired up and does move.
    if base_url:
        with contextlib.suppress(Exception):
            client.nonprofits.check("411787097")

    heading("Network activity")
    field("HTTP requests sent", transport.requests_sent)
    field("expected", "1 (the single valid call at the end)" if base_url else "0")

    client.close()

    note(
        "Validation is about shape only. `is_valid_ein` returning True means the value\n"
        "looks like an EIN — not that the organization exists, is exempt, or is the one\n"
        "your applicant claims to be."
    )

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
