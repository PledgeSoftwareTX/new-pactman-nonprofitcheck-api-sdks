"""
EX-08 — Automatic revocation detected.

An organization that fails to file for three consecutive years has its exemption
revoked automatically and appears in the IRS Automatic Revocation of Exemption
(AROE) data. The API reports that with ``revocation_code`` and
``revocation_date``.

This example flags the record and preserves the source fields verbatim. It does
not decide the outcome — blocking, holding, or reviewing is your policy.

Run:  PACTMAN_API_KEY=... python examples/ex_08_automatic_revocation.py
"""

from __future__ import annotations

import json
from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Any

from lib.fixture_api import FIXTURE_EINS, fixture_api
from lib.print import field, heading, note, pick

from pactman_nonprofit_check_plus import Nonprofit, get_aroe, get_bmf, get_pub78

# The application's policy, in one place, expressed against source fields.
ON_REVOKED_WITHOUT_REINSTATEMENT = "block"
ON_REVOKED_WITH_REINSTATEMENT = "manual_review"
ON_NO_REVOCATION_DATA = "continue"

AUDITED_FIELDS = [
    "revocation_code",
    "revocation_date",
    "reinstatement_date",
    "aroe_list_published_date",
    "bmf_status",
    "pub78_verified",
]


@dataclass(frozen=True)
class Assessment:
    action: str
    reason: str
    aroe: dict[str, Any] | None


def assess_revocation(nonprofit: Nonprofit) -> Assessment:
    aroe = get_aroe(nonprofit)

    if aroe is None:
        return Assessment(
            ON_NO_REVOCATION_DATA, "No revocation fields were returned.", None
        )

    record = dict(aroe)
    revoked = bool(record.get("revocation_code")) or bool(record.get("revocation_date"))

    if not revoked:
        return Assessment(
            ON_NO_REVOCATION_DATA, "Revocation fields were returned and are empty.", record
        )

    if record.get("reinstatement_date"):
        return Assessment(
            ON_REVOKED_WITH_REINSTATEMENT,
            "Revoked, with a reinstatement date present — see ex-09.",
            record,
        )

    return Assessment(
        ON_REVOKED_WITHOUT_REINSTATEMENT,
        "Appears in the Automatic Revocation data with no reinstatement.",
        record,
    )


def main() -> int:
    with fixture_api() as client:
        for ein in (FIXTURE_EINS["revoked"], FIXTURE_EINS["public_charity"]):
            result = client.nonprofits.check(ein)
            nonprofit = result.nonprofit

            if nonprofit is None:
                print(f"No record for {ein}.")
                continue

            assessment = assess_revocation(nonprofit)

            heading(f"{nonprofit.get('organization_name')} ({nonprofit.get('ein')})")
            field("revocation_code", pick(assessment.aroe, "revocation_code"))
            field("revocation_date", pick(assessment.aroe, "revocation_date"))
            field("reinstatement_date", pick(assessment.aroe, "reinstatement_date"))
            field("aroe_list_published_date", pick(assessment.aroe, "list_published_date"))

            # Revocation shows up in the other sources too. Capture what each one
            # said, rather than letting one field speak for all of them.
            bmf = get_bmf(nonprofit)
            field("bmf_status", pick(bmf, "status"))
            field("pub78_verified", pick(get_pub78(nonprofit), "verified"))
            field("exempt_status_code", pick(bmf, "exempt_status_code"))

            field("policy action", assessment.action)
            field("reason", assessment.reason)

            # What you keep is what you can explain later. Store the source
            # fields, the request identifier, and the time you looked — not just
            # the verdict.
            audit_record = {
                "ein": nonprofit.get("ein"),
                "checked_at": datetime.now(timezone.utc).isoformat(),
                "request_id": result.request_id,
                "action": assessment.action,
                # Absent keys stay absent, so the record cannot imply the API
                # returned a null it never sent.
                "source_findings": {
                    key: nonprofit[key]  # type: ignore[literal-required]
                    for key in AUDITED_FIELDS
                    if key in nonprofit
                },
            }

            print("\n  audit record:")

            for line in json.dumps(audit_record, indent=2).splitlines():
                print(f"    {line}")

    note(
        "The SDK reports what the AROE data says. It does not decide whether a revoked\n"
        "organization may receive a donation, a grant, or a payout — that is a legal and\n"
        "compliance determination your application owns."
    )

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
