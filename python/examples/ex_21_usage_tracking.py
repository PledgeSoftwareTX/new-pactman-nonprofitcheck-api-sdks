"""
EX-21 — Billing-cycle usage tracking.

``nonprofit_check_count``, surfaced as ``result.check_count``, is the running
total of checks your account has consumed so far in the current billing cycle.
It is never the size of the request you just made.

The test is one thing: fetch one nonprofit by EIN, and confirm the API sent that
counter as a JSON number. The SDK maps anything else to ``None``, which
downstream is indistinguishable from "not reported", so the check reads the
uncoerced value off ``raw``. This example exits non-zero when it is not a number.

Run:  PACTMAN_API_KEY=... python examples/ex_21_usage_tracking.py [EIN]
"""

from __future__ import annotations

import json
import sys
from typing import Any

from lib.client import create_client
from lib.fixture_api import FIXTURE_EINS
from lib.print import NOT_RETURNED, field, heading, note, pick


def json_type(value: Any) -> str:
    """The JSON type of a value, in the vocabulary the response contract uses."""
    if value is None:
        return "null"

    # Before int: ``True`` is an ``int`` in Python, and a boolean counter is not
    # a number the API is allowed to send.
    if isinstance(value, bool):
        return "boolean"

    if isinstance(value, (int, float)):
        return "number"

    if isinstance(value, str):
        return "string"

    if isinstance(value, (list, tuple)):
        return "array"

    if isinstance(value, dict):
        return "object"

    return type(value).__name__


def main() -> int:
    ein = sys.argv[1] if len(sys.argv) > 1 else FIXTURE_EINS["public_charity"]

    with create_client() as client:
        result = client.nonprofits.check(ein)

    # ``check_count`` is ``int | None``, and the SDK produces that ``None`` both
    # for a counter the API sent as null and for one it sent as ``"42"``. Only
    # ``raw``, which nothing has coerced, tells them apart.
    envelope = result.raw if isinstance(result.raw, dict) else None
    wire_value = pick(envelope, "nonprofit_check_count")
    wire_type = "<not returned>" if wire_value is NOT_RETURNED else json_type(wire_value)

    heading("nonprofit_check_count on the wire")
    field("ein", ein)
    field("wire type", wire_type)
    field("check_count", result.check_count)

    note(
        "The counter is cumulative for the billing cycle and resets when a new one starts.\n"
        "A bulk call for five EINs does not return 5 — it returns your cycle total."
    )

    if wire_type != "number":
        detail = "" if wire_value is NOT_RETURNED else f" {json.dumps(wire_value)}"
        print(
            f"\nnonprofit_check_count arrived as {wire_type}{detail}, not a number,"
            " so check_count reads None.",
            file=sys.stderr,
        )

        return 1

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
