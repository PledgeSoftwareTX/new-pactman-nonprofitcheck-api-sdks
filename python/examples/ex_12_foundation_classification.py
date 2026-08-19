"""
EX-12 — Organization type and foundation classification.

A grantmaker or DAF needs the classification on screen: public charity or private
foundation, which 509(a) paragraph, which deductibility limitation. The SDK maps
every one of those fields and declares none of them grant-eligible.

Note which values are read from the API's own ``*_description`` fields rather
than a local table. Descriptions the source supplies stay correct when the source
changes; a lookup table in your repository does not.

Run:  PACTMAN_API_KEY=... python examples/ex_12_foundation_classification.py
"""

from __future__ import annotations

from typing import Any

from lib.fixture_api import FIXTURE_EINS, fixture_api
from lib.irs_codes import describe_deductibility_status, describe_pf_filing_requirement
from lib.print import field, heading, note, pick

from pactman_nonprofit_check_plus import Nonprofit, get_bmf, get_pub78


def classification_panel(nonprofit: Nonprofit) -> dict[str, Any]:
    """What a grant officer sees. Every value is copied, none is computed."""
    bmf = get_bmf(nonprofit)
    pub78 = get_pub78(nonprofit)

    return {
        "subsection code": pick(bmf, "subsection"),
        "subsection description": pick(bmf, "subsection_description"),
        "foundation code": pick(bmf, "foundation_code"),
        "foundation code description": pick(bmf, "foundation_code_description"),
        "foundation type code": pick(bmf, "foundation_type_code"),
        "foundation type description": pick(bmf, "foundation_type_description"),
        "509(a) status": pick(bmf, "foundation_509a_status"),
        "deductibility text": pick(bmf, "deductability_text"),
        "990-PF filing requirement": describe_pf_filing_requirement(
            pick(bmf, "pf_filing_req_cd")
        ).display,
        "Pub 78 org type 1": describe_deductibility_status(
            pick(pub78, "source_org_type_1")
        ).display,
    }


def main() -> int:
    with fixture_api() as client:
        for ein in (FIXTURE_EINS["public_charity"], FIXTURE_EINS["private_foundation"]):
            nonprofit = client.nonprofits.check(ein).nonprofit

            if nonprofit is None:
                print(f"No record for {ein}.")
                continue

            heading(f"{nonprofit.get('organization_name')} ({nonprofit.get('ein')})")

            for label, value in classification_panel(nonprofit).items():
                field(label, value)

            heading("  organization_types")

            types = pick(get_pub78(nonprofit), "organization_types")
            types = types if isinstance(types, list) else []

            if not types:
                print("    none returned")
            else:
                for index, entry in enumerate(types):
                    status = pick(entry, "deductibility_status_description")
                    limitation = pick(entry, "deductibility_limitation")
                    print(f"    [{index}] status={status} limitation={limitation}")

            # A DAF's own rules live here, and they are visibly the DAF's. A
            # private foundation grantee is not disqualified — it is routed
            # differently, because expenditure responsibility and the
            # deductibility limit both change.
            bmf = get_bmf(nonprofit)
            is_private_foundation = (
                pick(bmf, "foundation_type_code") == "pf"
                or pick(bmf, "pf_filing_req_cd") == "1"
            )

            field(
                "\nthis application routes to",
                "private-foundation workflow — expenditure responsibility review"
                if is_private_foundation
                else "standard public-charity workflow",
            )

    note(
        "Displaying a classification is not asserting grant eligibility. The SDK reports\n"
        "the IRS classification; whether a grant may be made, and on what terms, is your\n"
        "grantmaking policy and your counsel's call."
    )

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
