"""
EX-06 — IRS Business Master File status inspection.

Reads every BMF field the response carries: status, identity, subsection,
exemption, ruling and foundation classification.

There is no ``is_exempt`` here and none in the SDK. ``bmf_status`` is one
source's answer to one question; an organization can be listed in the BMF and
still be revoked, sanctioned, or in conflict with Publication 78.

Run:  PACTMAN_API_KEY=... python examples/ex_06_bmf_status.py [EIN]
"""

from __future__ import annotations

import sys

from lib.client import create_client
from lib.fixture_api import FIXTURE_EINS
from lib.irs_codes import (
    describe_exempt_status,
    describe_filing_requirement,
    describe_pf_filing_requirement,
    format_ruling_date,
)
from lib.print import field, heading, note, pick

from pactman_nonprofit_check_plus import get_bmf


def main() -> int:
    ein = sys.argv[1] if len(sys.argv) > 1 else FIXTURE_EINS["public_charity"]

    with create_client() as client:
        nonprofit = client.nonprofits.check(ein).nonprofit

    if nonprofit is None:
        print(f"No record for EIN {ein}.")
        return 0

    bmf = get_bmf(nonprofit)

    if bmf is None:
        # Not "not in the BMF" — the API returned no BMF fields at all. Those are
        # different findings and this example refuses to merge them.
        print("The response carried no Business Master File data for this organization.")
        print("That is an absence of evidence, not a negative finding. Route it to review.")
        return 0

    heading("BMF status")
    field("bmf_status", pick(bmf, "status"))
    field("exempt_status_code", describe_exempt_status(pick(bmf, "exempt_status_code")).display)
    field("bmf_deductability_text", pick(bmf, "deductability_text"))
    field("most_recent_bmf", pick(bmf, "most_recent"))

    heading("BMF identity")
    field("bmf_organization_name", pick(bmf, "organization_name"))
    field("bmf_ein", pick(bmf, "ein"))
    field("bmf_street_address", pick(bmf, "street_address"))
    field("bmf_city", pick(bmf, "city"))
    field("bmf_state", pick(bmf, "state"))
    field("bmf_church_message", pick(bmf, "church_message"))

    heading("Subsection")
    field("bmf_subsection", pick(bmf, "subsection"))
    field("subsection_description", pick(bmf, "subsection_description"))

    heading("Exemption and ruling")
    field(
        "ruling date (year-month)",
        format_ruling_date(pick(bmf, "ruling_month"), pick(bmf, "ruling_year")),
    )
    field("ruling_month", pick(bmf, "ruling_month"))
    field("ruling_year", pick(bmf, "ruling_year"))
    field("group_exemption", pick(bmf, "group_exemption"))

    heading("Foundation classification")
    field("foundation_code", pick(bmf, "foundation_code"))
    field("foundation_code_description", pick(bmf, "foundation_code_description"))
    field("foundation_type_code", pick(bmf, "foundation_type_code"))
    field("foundation_type_description", pick(bmf, "foundation_type_description"))
    field("foundation_509a_status", pick(bmf, "foundation_509a_status"))

    heading("Filing requirements")
    field("filing_req_code", describe_filing_requirement(pick(bmf, "filing_req_code")).display)
    field(
        "bmf_source_pf_filing_req_cd",
        describe_pf_filing_requirement(pick(bmf, "pf_filing_req_cd")).display,
    )

    # Every value above came straight off the response. Turning them into an
    # approve/decline decision is the next step, and it belongs in your policy
    # code — see ex-26 for a worked routing example.
    note(
        "The BMF is one of four sources this API reports. Reading it in isolation is how\n"
        "a revoked or sanctioned organization passes a check: see ex-08 and ex-10."
    )

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
