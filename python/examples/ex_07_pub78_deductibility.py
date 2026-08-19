"""
EX-07 — Publication 78 and deductibility review.

Publication 78 is the IRS list of organizations eligible to receive
tax-deductible charitable contributions, together with the limitation that
applies. A donation or grant workflow reads it to decide what to tell a donor —
and the deciding is the workflow's job, not the SDK's.

Run:  PACTMAN_API_KEY=... python examples/ex_07_pub78_deductibility.py [EIN]
"""

from __future__ import annotations

import sys

from lib.client import create_client
from lib.fixture_api import FIXTURE_EINS
from lib.irs_codes import describe_deductibility_status
from lib.print import bullet, field, heading, note, pick

from pactman_nonprofit_check_plus import get_pub78


def main() -> int:
    ein = sys.argv[1] if len(sys.argv) > 1 else FIXTURE_EINS["public_charity"]

    with create_client() as client:
        nonprofit = client.nonprofits.check(ein).nonprofit

    if nonprofit is None:
        print(f"No record for EIN {ein}.")
        return 0

    pub78 = get_pub78(nonprofit)

    if pub78 is None:
        print("The response carried no Publication 78 data for this organization.")
        return 0

    heading("Publication 78 verification")
    field("pub78_verified", pick(pub78, "verified"))
    field("pub78_organization_name", pick(pub78, "organization_name"))
    field("pub78_ein", pick(pub78, "ein"))
    field("pub78_city", pick(pub78, "city"))
    field("pub78_state", pick(pub78, "state"))
    field("pub78_indicator", pick(pub78, "indicator"))
    field("pub78_church_message", pick(pub78, "church_message"))
    field("most_recent_pub78", pick(pub78, "most_recent"))

    heading("Source organization types")

    for slot in (1, 2, 3):
        code = pick(pub78, f"source_org_type_{slot}")
        field(f"pub78_source_org_type_{slot}", describe_deductibility_status(code).display)

    heading("Deductibility entries")

    entries = pick(pub78, "organization_types")
    entries = entries if isinstance(entries, list) else []

    if not entries:
        print("  No deductibility entries were returned.")
    else:
        for index, entry in enumerate(entries):
            code = pick(entry, "deductibility_status_description")
            status = describe_deductibility_status(code)

            print(f"  [{index}]")
            field("  deductibility_status_description", status.display, 34)
            field("  deductibility_limitation", pick(entry, "deductibility_limitation"), 34)
            field("  organization_type", pick(entry, "organization_type"), 34)

    # Your policy, expressed against the source data. Change the predicate, not
    # the SDK — nothing here is a verdict the API handed down.
    heading("Applying a donation policy")

    accepted_limitations = ["50%", "60%"]

    limitations = [
        entry["deductibility_limitation"]
        for entry in entries
        if isinstance(entry, dict) and entry.get("deductibility_limitation") is not None
    ]

    listed = pick(pub78, "verified") is True
    limitation_accepted = any(value in accepted_limitations for value in limitations)

    bullet(f"listed in Publication 78: {listed}")
    bullet(f"limitations returned: {', '.join(limitations) or 'none'}")
    bullet(f"limitation accepted by this policy: {limitation_accepted}")

    field(
        "policy outcome",
        "eligible under this application's own donation policy"
        if listed and limitation_accepted
        else "route to review — this application's policy is not satisfied by the "
        "returned data",
    )

    note(
        "The SDK maps Publication 78 data and stops there. Whether a classification\n"
        "satisfies your donor communications, your grant agreement, or your tax\n"
        "reporting obligations is a determination for your own counsel."
    )

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
