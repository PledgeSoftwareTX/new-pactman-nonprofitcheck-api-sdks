"""
EX-30 — Scheduled portfolio re-verification and audit trail.

A platform or consultant rechecks every onboarded organization on its own
schedule, records what changed in status, revocation, reinstatement, OFAC,
identity, classification and data freshness, and writes an audit entry it can
still explain a year later.

What makes an audit trail useful is not the outcome — it is the evidence next to
the outcome: when the check ran, which request it was, what each source said,
which policy version applied, and what changed since last time.

Run:  PACTMAN_API_KEY=... python examples/ex_30_portfolio_reverification.py
"""

from __future__ import annotations

from datetime import datetime, timedelta, timezone
from typing import Any

from lib.fixture_api import FIXTURE_EINS, fixture_api
from lib.print import bullet, field, heading, note, render
from lib.screening import MATERIAL_FIELDS, collect_findings, concerns, diff_findings

from pactman_nonprofit_check_plus import MAX_BULK_EINS

POLICY_VERSION = "2026.02-portfolio-rev3"
"""Identify the rules that produced an outcome, so old entries stay readable."""

RE_REVIEW_INTERVAL_DAYS = 90

PORTFOLIO: list[dict[str, Any]] = [
    {
        "ein": FIXTURE_EINS["public_charity"],
        "onboarded_at": "2025-11-02",
        "last_findings": None,
    },
    {
        "ein": FIXTURE_EINS["public_charity_second"],
        "onboarded_at": "2025-12-14",
        "last_findings": None,
    },
    {
        "ein": FIXTURE_EINS["private_foundation"],
        "onboarded_at": "2026-01-09",
        "last_findings": None,
    },
    {
        "ein": FIXTURE_EINS["reinstated"],
        "onboarded_at": "2025-09-30",
        # Stored at the previous run, before the reinstatement was published.
        "last_findings": {
            "organization_name": "SECOND CHANCE EXAMPLE ALLIANCE",
            "bmf_status": True,
            "exempt_status_code": "01",
            "pub78_verified": True,
            "revocation_code": "01",
            "revocation_date": "2/06/2022 9:41:03 PM",
            "reinstatement_date": None,
            "ofac_state": "no_match",
            "irs_bmf_pub78_conflict": False,
            "foundation_type_code": "pc",
            "subsection_description": "501(c)(3) Public Charity",
        },
    },
    {"ein": FIXTURE_EINS["ofac_match"], "onboarded_at": "2026-02-01", "last_findings": None},
    {"ein": FIXTURE_EINS["no_record"], "onboarded_at": "2025-08-21", "last_findings": None},
]
"""The portfolio, with whatever the last run stored."""


def batch(eins: list[str], size: int = MAX_BULK_EINS) -> list[list[str]]:
    """Splits the portfolio into requests the server will accept."""
    return [eins[index : index + size] for index in range(0, len(eins), size)]


def outcome_for(findings: dict[str, Any], changes: list[dict[str, Any]]) -> str:
    if findings["ofac_state"] == "match":
        return "suspend"

    if findings["revoked"] and not findings["reinstated"]:
        return "suspend"

    if changes or concerns(findings):
        return "review"

    return "retain"


def main() -> int:
    run_started_at = datetime.now(timezone.utc)
    audit_log: list[dict[str, Any]] = []
    batches = batch([entry["ein"] for entry in PORTFOLIO])

    heading("Re-verification run")
    field("policy version", POLICY_VERSION)
    field("interval (days)", RE_REVIEW_INTERVAL_DAYS)
    field("organizations", len(PORTFOLIO))
    field("batches", len(batches))
    field("started at", run_started_at.isoformat())

    records: dict[str, dict[str, Any]] = {}
    last_check_count: int | None = None

    with fixture_api() as client:
        for index, eins in enumerate(batches):
            result = client.nonprofits.check_bulk(eins)

            last_check_count = result.check_count

            for org in result.organizations:
                records[str(org.get("ein"))] = {
                    "org": org,
                    "request_id": result.request_id,
                    "status": result.status,
                }

            # An EIN that produced no record is recorded as unverified, not clean.
            for missing in result.not_found_eins:
                records[missing] = {
                    "org": None,
                    "request_id": result.request_id,
                    "status": result.status,
                }

            print(
                f"  batch {index + 1}: sent {len(eins)},"
                f" matched {len(result.organizations)},"
                f" missing {len(result.not_found_eins)}, request {result.request_id}"
            )

    for entry in PORTFOLIO:
        record = records.get(entry["ein"])

        heading(f"{entry['ein']} (onboarded {entry['onboarded_at']})")

        if record is None or record["org"] is None:
            field("outcome", "review")
            bullet(
                "No record returned. The organization is unverified this cycle, "
                "not cleared."
            )

            audit_log.append(
                {
                    "ein": entry["ein"],
                    "checked_at": run_started_at.isoformat(),
                    "request_id": record["request_id"] if record else None,
                    "policy_version": POLICY_VERSION,
                    "outcome": "review",
                    "reason": "no_record_returned",
                    "changes": [],
                    "findings": None,
                }
            )
            continue

        findings = collect_findings(record["org"], run_started_at.replace(tzinfo=None))
        changes = diff_findings(entry["last_findings"], findings, MATERIAL_FIELDS)
        open_concerns = concerns(findings)

        # A first run has nothing to compare against; say so rather than
        # reporting every field as "changed".
        is_baseline = entry["last_findings"] is None

        field("organization", findings["organization_name"])
        field("baseline run", is_baseline)
        field("changes since last run", "<no prior snapshot>" if is_baseline else len(changes))

        if not is_baseline:
            for change in changes:
                bullet(
                    f"{change['field']}: {render(change['before'])} → {render(change['after'])}"
                )

        field("bmf_status", findings["bmf_status"])
        field("pub78_verified", findings["pub78_verified"])
        field("revocation_date", findings["revocation_date"])
        field("reinstatement_date", findings["reinstatement_date"])
        field("ofac state", findings["ofac_state"])
        field("conflict flag", findings["irs_bmf_pub78_conflict"])
        field("classification", findings["subsection_description"])
        field("oldest source (days)", findings["oldest_source_age_days"])
        field("report_date", findings["report_date"])

        for concern in open_concerns:
            bullet(f"concern: {concern}")

        outcome = outcome_for(findings, [] if is_baseline else changes)

        field("outcome", outcome)

        # The entry a consultant can produce when asked, months later, why an
        # organization was suspended or retained.
        audit_log.append(
            {
                "ein": entry["ein"],
                "checked_at": run_started_at.isoformat(),
                "request_id": record["request_id"],
                "http_status": record["status"],
                "policy_version": POLICY_VERSION,
                "outcome": outcome,
                "concerns": open_concerns,
                "changes": [] if is_baseline else changes,
                "findings": findings,
                "next_review_due": (
                    run_started_at + timedelta(days=RE_REVIEW_INTERVAL_DAYS)
                ).isoformat(),
            }
        )

        # Carry the snapshot forward, so the next run has something to diff against.
        entry["last_findings"] = findings

    heading("Audit log")
    print(f"  {'ein'.ljust(12)} {'outcome'.ljust(9)} {'changes'.ljust(8)} request")

    for record in audit_log:
        print(
            f"  {record['ein'].ljust(12)} {record['outcome'].ljust(9)}"
            f" {str(len(record['changes'])).ljust(8)} {record['request_id'] or '<none>'}"
        )

    heading("Run summary")
    field("entries written", len(audit_log))
    field("suspended", sum(1 for r in audit_log if r["outcome"] == "suspend"))
    field("to review", sum(1 for r in audit_log if r["outcome"] == "review"))
    field("retained", sum(1 for r in audit_log if r["outcome"] == "retain"))
    field("checks used this cycle", last_check_count)
    field("next run due", audit_log[0].get("next_review_due") if audit_log else None)

    bullet("Request identifiers are stored; API keys are not, and never appear here.")

    note(
        "The audit trail records what the sources said and which policy read them. It is\n"
        "evidence of a process, not a legal determination — the SDK supplies the former\n"
        "and takes no position on the latter."
    )

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
