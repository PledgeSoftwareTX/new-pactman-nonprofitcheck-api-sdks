"""
EX-03 — Basic nonprofit identity lookup.

Retrieves an organization and reads its identity fields. The typed model and the
untouched response body are both available; neither replaces the other.

Run:  PACTMAN_API_KEY=... python examples/ex_03_identity_lookup.py [EIN]
"""

from __future__ import annotations

import sys
from typing import Any, cast

from lib.client import create_client
from lib.fixture_api import FIXTURE_EINS
from lib.print import field, heading, note, pick


def main() -> int:
    ein = sys.argv[1] if len(sys.argv) > 1 else FIXTURE_EINS["public_charity"]

    with create_client() as client:
        result = client.nonprofits.check(ein)

    if result.nonprofit is None:
        print(f"No record for EIN {ein}.")
        return 0

    nonprofit = result.nonprofit

    heading("Identity")
    field("ein", pick(nonprofit, "ein"))
    field("organization_name", pick(nonprofit, "organization_name"))
    field("organization_name_aka", pick(nonprofit, "organization_name_aka"))
    field("pactman_org_url", pick(nonprofit, "pactman_org_url"))

    # `organization_name_aka` is frequently null. That is "the API has no
    # alternate name on file", not "the organization has no alternate name".

    heading("Response metadata")
    field("status", result.status)
    field("request_id", result.request_id)
    field("time_taken_ms", result.time_taken_ms)
    field("check_count", result.check_count)

    # The structured model is a view over the envelope, not a replacement for it.
    # `raw` is exactly what the server sent, including anything not typed above.
    raw = cast(dict[str, Any], result.raw) if isinstance(result.raw, dict) else {}
    data = raw.get("data")

    heading("Raw envelope")
    field("raw['code']", pick(raw, "code"))
    field("raw['message']", pick(raw, "message"))
    field("raw['data']['ein']", pick(data if isinstance(data, dict) else None, "ein"))
    field("fields returned", len(nonprofit))

    note(
        "A returned profile URL means Pactman holds a page for the organization. It is\n"
        "not an endorsement, and not a statement about tax-exempt status."
    )

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
