"""
EX-17 — Bulk screening of a grantee or nonprofit list.

The shape of the work a grantmaker, DAF, employee-giving platform or migrating
consultant actually does: hand the API a list of EINs, walk the organizations
that came back, and keep the response-level metadata.

One bulk request is one round trip and one rate-limit slot. Prefer it to a loop
of single checks.

Run:  PACTMAN_API_KEY=... python examples/ex_17_bulk_screening.py
"""

from __future__ import annotations

import json
import re
from typing import Any, cast

from lib.fixture_api import FIXTURE_EINS, fixture_api
from lib.print import field, heading, note, pick

from pactman_nonprofit_check_plus import (
    MAX_BULK_EINS,
    get_aroe,
    get_bmf,
    get_ofac,
    get_pub78,
)

_UID = re.compile(r"UID:")


def main() -> int:
    # A grantee portfolio as it might arrive from a spreadsheet import.
    portfolio: list[dict[str, str]] = [
        {"ein": FIXTURE_EINS["public_charity"], "grantee": "Meals Today"},
        {"ein": FIXTURE_EINS["public_charity_second"], "grantee": "Aborjaily Fund"},
        {"ein": FIXTURE_EINS["private_foundation"], "grantee": "Hartwell Family Foundation"},
        {"ein": FIXTURE_EINS["revoked"], "grantee": "Lapsed Filings Society"},
        {"ein": FIXTURE_EINS["no_record"], "grantee": "Unknown Org From The Import"},
    ]

    eins = [entry["ein"] for entry in portfolio]

    with fixture_api() as client:
        heading(f"Screening {len(eins)} EINs (server limit is {MAX_BULK_EINS} per request)")

        result = client.nonprofits.check_bulk(eins)

        # Response-level envelope fields, all reachable.
        raw = cast(dict[str, Any], result.raw) if isinstance(result.raw, dict) else {}

        field("status", result.status)
        field("raw['code']", pick(raw, "code"))
        field("raw['message']", pick(raw, "message"))
        field("timeTaken (ms)", result.time_taken_ms)
        field("nonprofit_check_count", result.check_count)
        field("organizations returned", len(result.organizations))
        field("item-level errors", len(result.errors))
        field("not_found_eins", ", ".join(result.not_found_eins) or "<none>")

        # Index by EIN. The response is a set of matched records, not a
        # row-for-row answer to your input list — see ex-18.
        by_ein = {org.get("ein"): org for org in result.organizations}

        heading("Organization-level results")

        for entry in portfolio:
            org = by_ein.get(entry["ein"])

            if org is None:
                print(f"  {entry['ein']}  {entry['grantee'].ljust(28)} no record returned")
                continue

            bmf = get_bmf(org)
            pub78 = get_pub78(org)
            aroe = get_aroe(org)
            ofac = get_ofac(org)

            status = pick(ofac, "status")

            if not isinstance(status, str):
                ofac_label = "unscreened"
            else:
                ofac_label = "POSSIBLE MATCH" if _UID.search(status) else "no match"

            name = str(org.get("organization_name"))[:28].ljust(28)

            print(
                f"  {org.get('ein')}  {name}"
                f" bmf={pick(bmf, 'status')}  pub78={pick(pub78, 'verified')}"
                f"  revoked={bool(pick(aroe, 'revocation_date'))}"
                f"  ofac={ofac_label}"
                f"  conflict={org.get('irs_bmf_pub78_conflict')}"
            )

        heading("Item-level errors, verbatim")

        for detail in result.errors:
            print(f"  resource={detail.get('resource')}")
            print(f"  code={detail.get('code', '<none>')}")
            print(f"  reason={detail.get('reason')}")
            print(f"  eins={json.dumps(detail.get('eins'))}")

        if not result.errors:
            print("  none")

    note(
        "This is a screening pass, not an approval pass. Each row above is source data\n"
        "for your grant policy to act on — ex-27 shows one worked routing."
    )

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
