"""
EX-19 — Bulk partial success and item-level errors.

A bulk request where some EINs matched and some did not is a success. It comes
back as HTTP 200 with organizations in ``data`` and the failures in ``errors``.

The successful records are fully usable. The failures keep the input EIN, so you
can reconcile every row of your input against an outcome instead of discovering
later that a grantee was silently skipped.

Run:  PACTMAN_API_KEY=... python examples/ex_19_bulk_partial_success.py
"""

from __future__ import annotations

import json
from typing import Any, cast

from lib.fixture_api import FIXTURE_EINS, fixture_api
from lib.print import bullet, field, heading, note, pick, render

from pactman_nonprofit_check_plus import get_aroe, get_bmf, get_pub78


def main() -> int:
    submitted = [
        FIXTURE_EINS["public_charity"],
        FIXTURE_EINS["no_record"],
        FIXTURE_EINS["revoked"],
        "123456789",
        FIXTURE_EINS["public_charity_second"],
    ]

    with fixture_api() as client:
        result = client.nonprofits.check_bulk(submitted)

        raw = cast(dict[str, Any], result.raw) if isinstance(result.raw, dict) else {}

        heading("Mixed outcome")
        field("HTTP status", result.status)
        field("envelope code", pick(raw, "code"))
        field("envelope message", pick(raw, "message"))
        field("submitted", len(submitted))
        field("matched", len(result.organizations))
        field("item-level errors", len(result.errors))
        field("not_found_eins", ", ".join(result.not_found_eins))

        # Successful records are ordinary records. Nothing about a sibling
        # failure degrades them.
        heading("Successful records remain fully usable")

        for org in result.organizations:
            bmf = get_bmf(org)
            pub78 = get_pub78(org)
            aroe = get_aroe(org)

            print(f"  {org.get('ein')}  {org.get('organization_name')}")
            print(
                f"    bmf_status={pick(bmf, 'status')}"
                f"  pub78_verified={pick(pub78, 'verified')}"
                f"  revocation_date={render(pick(aroe, 'revocation_date'))}"
            )

        heading("Failures, with their structured detail")

        for detail in result.errors:
            bullet(f"resource: {detail.get('resource')}")
            bullet(f"code: {detail.get('code', '<none>')}")
            bullet(f"reason: {detail.get('reason')}")
            bullet(f"eins: {json.dumps(detail.get('eins'))}")

        # Reconcile every input against an outcome. This is the loop that keeps a
        # portfolio import honest.
        heading("Input reconciliation")

        matched = {org.get("ein") for org in result.organizations}
        missing = set(result.not_found_eins)
        unaccounted: list[str] = []

        for index, ein in enumerate(submitted):
            if ein in matched:
                outcome = "matched"
            elif ein in missing:
                outcome = "no record — reported in errors"
            else:
                outcome = "UNACCOUNTED FOR — do not treat as checked"
                unaccounted.append(ein)

            print(f"  input[{index}] {ein}  {outcome}")

        field("\nunaccounted inputs", len(unaccounted))

        if unaccounted:
            bullet("An input with no matching record and no error is not a pass. Re-check it.")

    note(
        "An EIN the API has no record for is a gap in the data, not a negative finding\n"
        'about the organization. Route it to review; do not record it as "screened".'
    )

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
