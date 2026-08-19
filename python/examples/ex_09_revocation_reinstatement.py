"""
EX-09 — Revoked organization with reinstatement data.

A record can carry both a revocation date and a reinstatement date. The two stay
separately accessible, because the gap between them matters: a donation made
while the exemption was revoked is not retroactively fixed by a later
reinstatement, and reinstatement can be retroactive or not.

This example surfaces both dates and the interval, and still routes the record to
review. Reinstatement resolves one question, not every question.

Run:  PACTMAN_API_KEY=... python examples/ex_09_revocation_reinstatement.py
"""

from __future__ import annotations

import json
from datetime import datetime, timezone

from lib.fixture_api import FIXTURE_EINS, fixture_api
from lib.print import bullet, field, heading, note, pick
from lib.screening import parse_api_date

from pactman_nonprofit_check_plus import get_aroe, get_bmf, get_pub78

RETAINED_FIELDS = [
    "revocation_date",
    "reinstatement_date",
    "revocation_code",
    "aroe_list_published_date",
]

QUESTIONS_REINSTATEMENT_DOES_NOT_ANSWER = [
    "Was the reinstatement retroactive to the revocation date?",
    "Do gifts made during the lapse need to be re-characterized?",
    "Does your grant agreement require continuous exemption?",
    "Has the organization filed since reinstatement?",
]


def main() -> int:
    with fixture_api() as client:
        result = client.nonprofits.check(FIXTURE_EINS["reinstated"])

    nonprofit = result.nonprofit

    if nonprofit is None:
        print("No record returned.")
        return 0

    aroe = get_aroe(nonprofit)

    heading(f"{nonprofit.get('organization_name')} ({nonprofit.get('ein')})")

    # Both dates are their own field. Nothing collapses them into a single
    # "currently revoked" boolean, because that boolean would lose the interval.
    field("revocation_code", pick(aroe, "revocation_code"))
    field("revocation_date", pick(aroe, "revocation_date"))
    field("reinstatement_date", pick(aroe, "reinstatement_date"))
    field("aroe_list_published_date", pick(aroe, "list_published_date"))

    revoked_at = parse_api_date(pick(aroe, "revocation_date"))
    reinstated_at = parse_api_date(pick(aroe, "reinstatement_date"))

    heading("Derived, in application code")

    if revoked_at and reinstated_at:
        bullet(f"revoked on {revoked_at.strftime('%Y-%m-%d')}")
        bullet(f"reinstated on {reinstated_at.strftime('%Y-%m-%d')}")
        bullet(f"exemption lapsed for {(reinstated_at - revoked_at).days} days")
        bullet("donations dated inside that window may need separate handling")
    elif revoked_at:
        bullet("revoked, with no reinstatement date returned")
    else:
        bullet("no revocation history returned")

    heading("What the other sources say now")
    field("bmf_status", pick(get_bmf(nonprofit), "status"))
    field("pub78_verified", pick(get_pub78(nonprofit), "verified"))
    field("irs_bmf_pub78_conflict", pick(nonprofit, "irs_bmf_pub78_conflict"))

    heading("Outcome")

    for question in QUESTIONS_REINSTATEMENT_DOES_NOT_ANSWER:
        bullet(question)

    field(
        "\npolicy action",
        "manual review — reinstatement is recorded, and the record still has history",
    )

    evidence = {
        "ein": nonprofit.get("ein"),
        "request_id": result.request_id,
        "checked_at": datetime.now(timezone.utc).isoformat(),
        **{
            key: nonprofit[key]  # type: ignore[literal-required]
            for key in RETAINED_FIELDS
            if key in nonprofit
        },
    }

    print("\n  evidence retained:")

    for line in json.dumps(evidence, indent=2).splitlines():
        print(f"    {line}")

    note(
        'The API answers "what does the IRS revocation data show". It does not answer\n'
        '"is this organization eligible today" — that needs your policy, and often your\n'
        "counsel."
    )

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
