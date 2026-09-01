"""
EX-21 — Billing-cycle usage tracking.

``nonprofit_check_count``, surfaced as ``result.check_count``, is the running
total of checks your account has consumed so far in the current billing cycle.
It is never the size of the request you just made.

The test is one thing: the API sends that counter as a JSON number. The SDK maps
anything else to ``None``, which downstream is indistinguishable from "not
reported", so the check reads the uncoerced value off ``raw``. This example
exits non-zero when any response fails it.

Run:  PACTMAN_API_KEY=... python examples/ex_21_usage_tracking.py
"""

from __future__ import annotations

import json
from typing import Any

from lib.fixture_api import FIXTURE_EINS, fixture_api
from lib.print import bullet, field, heading, note

from pactman_nonprofit_check_plus import PactmanResult


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


def wire_check_count(result: PactmanResult) -> str:
    """
    How ``nonprofit_check_count`` arrived, before this SDK read it.

    ``check_count`` is ``int | None``, and the SDK produces that ``None`` both
    for a counter the API sent as null and for one it sent as ``"42"``. Only
    ``raw``, which nothing has coerced, tells them apart.
    """
    envelope = result.raw

    if not isinstance(envelope, dict) or "nonprofit_check_count" not in envelope:
        return "<not returned>"

    value = envelope["nonprofit_check_count"]
    wire_type = json_type(value)

    return "number" if wire_type == "number" else f"{wire_type} {json.dumps(value)}"


def main() -> int:
    with fixture_api() as client:
        responses = [
            ("single check", client.nonprofits.check(FIXTURE_EINS["public_charity"])),
            ("single check", client.nonprofits.check(FIXTURE_EINS["public_charity_second"])),
            (
                "bulk check of 3",
                client.nonprofits.check_bulk(
                    [
                        FIXTURE_EINS["public_charity"],
                        FIXTURE_EINS["public_charity_second"],
                        FIXTURE_EINS["private_foundation"],
                    ]
                ),
            ),
            (
                "bulk with a miss",
                client.nonprofits.check_bulk(
                    [FIXTURE_EINS["revoked"], FIXTURE_EINS["no_record"]]
                ),
            ),
        ]

        samples = [
            {
                "label": label,
                "wire": wire_check_count(result),
                "check_count": result.check_count,
            }
            for label, result in responses
        ]

    heading("nonprofit_check_count on the wire")
    print(f"  {'request'.ljust(20)} {'wire type'.ljust(20)} check_count")

    for sample in samples:
        print(
            f"  {str(sample['label']).ljust(20)} {str(sample['wire']).ljust(20)}"
            f" {sample['check_count']}"
        )

    mistyped = [sample for sample in samples if sample["wire"] != "number"]

    heading("Verdict")
    field("responses inspected", len(samples))
    field("sent as a JSON number", len(samples) - len(mistyped))

    for sample in mistyped:
        bullet(f"{sample['label']}: the API sent {sample['wire']}, so check_count reads None")

    note(
        "The counter is cumulative for the billing cycle and resets when a new one starts.\n"
        "A bulk call for five EINs does not return 5 — it returns your cycle total."
    )

    if mistyped:
        print(
            f"\n{len(mistyped)} of {len(samples)} responses did not send"
            " nonprofit_check_count as a number."
        )

        return 1

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
