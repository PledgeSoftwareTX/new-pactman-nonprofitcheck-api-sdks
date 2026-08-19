"""
EX-14 — Data freshness and report metadata.

Every source on the response carries its own date. A check is a statement about
the data as of those dates — not as of the moment you called.

This example surfaces each timestamp, computes an age, and applies a re-review
rule the application owns. The SDK supplies the dates and nothing else: there is
no ``is_stale`` property and no default threshold, because 90 days is prudent for
one workflow and reckless for another.

Run:  PACTMAN_API_KEY=... python examples/ex_14_data_freshness.py
"""

from __future__ import annotations

import json
from datetime import datetime, timezone
from typing import Any

from lib.fixture_api import FIXTURE_EINS, fixture_api
from lib.print import bullet, field, heading, note
from lib.screening import parse_api_date

from pactman_nonprofit_check_plus import Nonprofit

RE_REVIEW_AFTER_DAYS = 90
"""The application's own rule. Change it here, in one place."""

TIMESTAMP_FIELDS = [
    "organization_info_last_modified",
    "report_date",
    "most_recent_bmf",
    "most_recent_pub78",
    "ofac_list_published_date",
    "aroe_list_published_date",
]


def age_in_days(value: Any, now: datetime) -> int | None:
    parsed = parse_api_date(value)

    return None if parsed is None else round((now - parsed).total_seconds() / 86_400)


def timestamps_of(nonprofit: Nonprofit) -> dict[str, Any]:
    return {name: nonprofit.get(name) for name in TIMESTAMP_FIELDS}


def main() -> int:
    cases = [
        ("recently refreshed", FIXTURE_EINS["public_charity"]),
        ("every source is old", FIXTURE_EINS["stale_data"]),
        ("some dates were not returned", FIXTURE_EINS["sparse_identity"]),
    ]

    with fixture_api() as client:
        for label, ein in cases:
            result = client.nonprofits.check(ein)
            nonprofit = result.nonprofit

            if nonprofit is None:
                print(f"No record for {ein}.")
                continue

            now = datetime.now()
            timestamps = timestamps_of(nonprofit)

            heading(f"{label} — {nonprofit.get('organization_name')}")

            for name, value in timestamps.items():
                age = age_in_days(value, now)
                shown = str(value if value is not None else "<null>").ljust(26)
                print(
                    f"  {name.ljust(34)} {shown}"
                    f" {'age unknown' if age is None else f'{age} days old'}"
                )

            # `report_date` is when this response was generated. The source dates
            # are when each underlying list was last refreshed. They answer
            # different questions, and the older one governs.
            ages = [
                (name, age_in_days(value, now))
                for name, value in timestamps.items()
                if age_in_days(value, now) is not None
            ]

            oldest = max(ages, key=lambda entry: entry[1] or 0) if ages else None
            undated = [name for name, value in timestamps.items() if not value]

            if oldest is not None:
                bullet(f"oldest source: {oldest[0]} at {oldest[1]} days")

            for name in undated:
                bullet(f"no date returned for {name} — age cannot be established")

            oldest_age = oldest[1] if oldest is not None else None
            needs_re_review = (
                oldest_age is None or oldest_age > RE_REVIEW_AFTER_DAYS or bool(undated)
            )

            field("request timing (timeTaken ms)", result.time_taken_ms)
            field("checked at (local)", now.isoformat())
            field(
                f"re-review rule (> {RE_REVIEW_AFTER_DAYS} days)",
                "schedule a re-review — a source is past the threshold or undated"
                if needs_re_review
                else "within the freshness window — no re-review scheduled",
            )

            # Store the timestamps alongside your verification record, not just
            # the outcome. Six months from now "we checked and it was fine" is
            # not an answer; "we checked on this date against BMF data published
            # on that date" is.
            if ein == FIXTURE_EINS["public_charity"]:
                record = {
                    "ein": nonprofit.get("ein"),
                    "checked_at": datetime.now(timezone.utc).isoformat(),
                    "request_id": result.request_id,
                    **timestamps,
                }

                print("\n  stored with the verification record:")

                for line in json.dumps(record, indent=2).splitlines():
                    print(f"    {line}")

    note(
        "A fresh response is not a fresh fact. IRS lists publish on their own schedule,\n"
        "so a check performed today can reflect a revocation posted weeks ago and not\n"
        "yet published — see ex-29 for the pre-payment recheck this implies."
    )

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
