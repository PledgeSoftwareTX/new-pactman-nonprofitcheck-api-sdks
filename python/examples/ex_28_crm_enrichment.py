"""
EX-28 — Nonprofit CRM enrichment or synchronization.

Uses a verified EIN as the stable key to refresh a CRM record with canonical
name, AKA, address, status, classification, profile URL and last-modified
metadata.

The rule that makes this safe to run on a schedule: a null from the API is an
absence of data, not an instruction to erase. A sync that overwrites a good,
human-entered address with null because one IRS field was empty is a data-loss
bug that looks like a feature until someone notices.

Run:  PACTMAN_API_KEY=... python examples/ex_28_crm_enrichment.py
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Any

from lib.fixture_api import FIXTURE_EINS, fixture_api
from lib.print import NOT_RETURNED, bullet, field, heading, note, pick, render

from pactman_nonprofit_check_plus import Nonprofit

SYNCED_FIELDS = [
    "organization_name",
    "organization_name_aka",
    "address_line1",
    "address_line2",
    "city",
    "state",
    "state_name",
    "zip",
    "subsection_description",
    "foundation_type_description",
    "bmf_status",
    "pub78_verified",
    "pactman_org_url",
    "organization_info_last_modified",
]
"""Fields this CRM keeps in sync, mapped to their source on the response."""


def _blank_row(ein: str, **overrides: Any) -> dict[str, Any]:
    row: dict[str, Any] = {"ein": ein, **{key: None for key in SYNCED_FIELDS}}
    row["verified_at"] = None
    row.update(overrides)

    return row


# Existing CRM rows, keyed by EIN. Some hold better data than the API returns.
CRM: dict[str, dict[str, Any]] = {
    FIXTURE_EINS["public_charity"]: _blank_row(
        FIXTURE_EINS["public_charity"],
        organization_name="Meals Today",
        address_line1="50 Lowell Ave",
        address_line2="Suite 3B",
        city="Westfield",
        state="MA",
        state_name="Massachusetts",
        zip="01085-2643",
    ),
    FIXTURE_EINS["sparse_identity"]: _blank_row(
        FIXTURE_EINS["sparse_identity"],
        organization_name="Quiet Harbor Trust",
        organization_name_aka="QHT",
        address_line1="PO Box 118",
        # Entered by a fundraiser who spoke to the organization. The API returns
        # null for these; that must not wipe them.
        city="Rockport",
        state="ME",
        state_name="Maine",
        zip="04856",
        verified_at="2026-01-04T09:12:00+00:00",
    ),
}


@dataclass(frozen=True)
class Merge:
    next: dict[str, Any]
    updates: list[dict[str, Any]]
    skipped: list[dict[str, str]]


def merge(record: dict[str, Any], nonprofit: Nonprofit) -> Merge:
    """
    Merges a response into a CRM row.

    A field is written only when the API returned a usable value. Null and
    absent both mean "no update available" — never "clear this".
    """
    updates: list[dict[str, Any]] = []
    skipped: list[dict[str, str]] = []
    next_row = dict(record)

    for key in SYNCED_FIELDS:
        incoming = pick(nonprofit, key)

        if incoming is None or incoming is NOT_RETURNED:
            skipped.append(
                {
                    "key": key,
                    "reason": "API returned null"
                    if incoming is None
                    else "API returned no field",
                }
            )
            continue

        if record.get(key) == incoming:
            continue

        updates.append({"key": key, "before": record.get(key), "after": incoming})
        next_row[key] = incoming

    return Merge(next_row, updates, skipped)


def main() -> int:
    eins = list(CRM)

    with fixture_api() as client:
        result = client.nonprofits.check_bulk(eins)

    # EIN is the join key: stable, returned on every record, and the same value
    # your CRM already stores. Names change; EINs do not.
    by_ein = {org.get("ein"): org for org in result.organizations}

    for ein in eins:
        record = CRM[ein]
        nonprofit = by_ein.get(ein)

        heading(f"CRM record {ein}")

        if nonprofit is None:
            # No record came back. Leave the row untouched and mark the attempt.
            field("sync", "skipped — no record returned")
            bullet("The existing CRM data is retained; a failed lookup is not new information.")
            CRM[ein] = {
                **record,
                "last_sync_attempt_at": datetime.now(timezone.utc).isoformat(),
            }
            continue

        merged = merge(record, nonprofit)

        # A verification timestamp, so downstream code can tell fresh rows from
        # rows nobody has touched since import.
        merged.next["verified_at"] = datetime.now(timezone.utc).isoformat()
        merged.next["verification_request_id"] = result.request_id
        merged.next["verification_report_date"] = nonprofit.get("report_date")

        CRM[ein] = merged.next

        field("fields updated", len(merged.updates))

        for update in merged.updates:
            bullet(f"{update['key']}: {render(update['before'])} → {render(update['after'])}")

        field("fields left alone", len(merged.skipped))

        for skip in merged.skipped:
            bullet(f"{skip['key']}: kept {render(record.get(skip['key']))} ({skip['reason']})")

        field("verified_at", merged.next["verified_at"])
        field("previous verified_at", record.get("verified_at"))

    heading("CRM after synchronization")

    for ein, record in CRM.items():
        print(f"  {ein}  {record['organization_name']}")
        print(
            f"    aka={render(record.get('organization_name_aka'))}"
            f"  city={render(record.get('city'))}"
            f"  zip={render(record.get('zip'))}"
            f"  bmf={render(record.get('bmf_status'))}"
        )
        print(f"    profile={render(record.get('pactman_org_url'))}")
        print(f"    verified_at={render(record.get('verified_at'))}")

    note(
        "Storing `verified_at` is what makes this data auditable. Without it, a row that\n"
        "was checked yesterday and a row imported from a spreadsheet in 2019 look\n"
        "identical — and only one of them is evidence."
    )

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
