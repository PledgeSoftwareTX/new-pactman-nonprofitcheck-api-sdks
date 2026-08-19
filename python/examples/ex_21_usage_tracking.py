"""
EX-21 — Billing-cycle usage tracking.

``nonprofit_check_count``, surfaced as ``result.check_count``, is the running
total of checks your account has consumed **so far in the current billing
cycle**. It resets to zero when a new cycle starts.

It is NOT the size of the request you just made. A bulk call for five EINs does
not return 5; it returns your cycle total including those five. Read it as a
gauge, and take the size of a request from the request.

Run:  PACTMAN_API_KEY=... python examples/ex_21_usage_tracking.py
"""

from __future__ import annotations

import os
from datetime import datetime, timezone
from typing import Any

from lib.fixture_api import FIXTURE_EINS, fixture_api
from lib.print import bullet, field, heading, note

from pactman_nonprofit_check_plus import PactmanResult


class Telemetry:
    """What an admin screen or a metrics exporter would hold."""

    def __init__(self) -> None:
        self.cycle_total: int | None = None
        self.observed_at: str | None = None
        self.samples: list[dict[str, Any]] = []

    def record(self, label: str, requested: int, result: PactmanResult) -> None:
        previous = self.cycle_total

        self.cycle_total = result.check_count
        self.observed_at = datetime.now(timezone.utc).isoformat()
        self.samples.append(
            {
                "label": label,
                "requested": requested,
                "cycle_total": result.check_count,
                "delta": None
                if previous is None or result.check_count is None
                else result.check_count - previous,
                "request_id": result.request_id,
            }
        )


def main() -> int:
    telemetry = Telemetry()

    with fixture_api() as client:
        telemetry.record(
            "single check", 1, client.nonprofits.check(FIXTURE_EINS["public_charity"])
        )
        telemetry.record(
            "single check", 1, client.nonprofits.check(FIXTURE_EINS["public_charity_second"])
        )
        telemetry.record(
            "bulk check",
            3,
            client.nonprofits.check_bulk(
                [
                    FIXTURE_EINS["public_charity"],
                    FIXTURE_EINS["public_charity_second"],
                    FIXTURE_EINS["private_foundation"],
                ]
            ),
        )
        telemetry.record(
            "bulk with a miss",
            2,
            client.nonprofits.check_bulk(
                [FIXTURE_EINS["revoked"], FIXTURE_EINS["no_record"]]
            ),
        )

    heading("nonprofit_check_count across four requests")
    print(f"  {'request'.ljust(20)} {'EINs sent'.ljust(11)} {'cycle total'.ljust(13)} delta")

    for sample in telemetry.samples:
        print(
            f"  {sample['label'].ljust(20)} {str(sample['requested']).ljust(11)}"
            f" {str(sample['cycle_total']).ljust(13)}"
            f" {sample['delta'] if sample['delta'] is not None else '—'}"
        )

    heading("Reading the numbers")
    bullet("The cycle total climbs across requests. It is cumulative, not per-request.")
    bullet("The delta is what a request consumed — derive it, or count what you sent.")
    bullet("EINs with no record are not billed, so a delta can be smaller than the batch.")
    bullet("At the start of a new billing cycle this counter resets to zero.")

    heading("Operational surface")
    field("checks used this cycle", telemetry.cycle_total)
    field("observed at", telemetry.observed_at)
    field("last request_id", telemetry.samples[-1]["request_id"] if telemetry.samples else None)

    # Alerting on the cycle total needs your plan's allowance, which the check
    # endpoints do not report. Keep it in your own configuration.
    plan_allowance = int(os.environ.get("PACTMAN_PLAN_ALLOWANCE") or 0)

    if plan_allowance > 0:
        used = telemetry.cycle_total or 0
        field("plan allowance", plan_allowance)
        field("utilisation", f"{round(used / plan_allowance * 100)}%")
        field(
            "alert",
            "over 80% of the cycle allowance"
            if used / plan_allowance > 0.8
            else "nominal",
        )
    else:
        bullet("Set PACTMAN_PLAN_ALLOWANCE to compute utilisation against your plan.")

    note(
        'Label this metric "checks used this billing cycle" wherever it is displayed.\n'
        'Labelling it "checks in this request" makes a dashboard that resets monthly\n'
        "look like a dashboard that is broken."
    )

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
