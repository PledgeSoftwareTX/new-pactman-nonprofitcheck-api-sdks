"""
Minimal single nonprofit check.

Run:  PACTMAN_API_KEY=... python examples/quickstart.py [EIN]

The key is read from the environment. Never hard-code it, and never run this
anywhere the key is exposed — it is a private server-side credential.
"""

from __future__ import annotations

import os
import sys

from pactman_nonprofit_check_plus import PactmanClient, get_bmf, get_ofac, get_pub78


def main() -> int:
    api_key = os.environ.get("PACTMAN_API_KEY")

    if not api_key:
        print("Set PACTMAN_API_KEY before running this example.", file=sys.stderr)
        return 1

    # Production is the default. PACTMAN_BASE_URL is only for a local mock server.
    base_url = os.environ.get("PACTMAN_BASE_URL")
    ein = sys.argv[1] if len(sys.argv) > 1 else "41-1787097"

    with PactmanClient(api_key=api_key, base_url=base_url, timeout=15.0) as client:
        result = client.nonprofits.check(ein)

    if result.nonprofit is None:
        print(f"No record for EIN {ein}.")
        return 0

    nonprofit = result.nonprofit

    print(f"Organization : {nonprofit['organization_name']}")
    print(f"EIN          : {nonprofit['ein']}")
    print(f"Location     : {nonprofit['city']}, {nonprofit['state']}")
    print(f"Profile      : {nonprofit['pactman_org_url']}")
    print(f"Checks used  : {result.check_count}")

    # Three source-specific findings, read straight from the API response.
    pub78 = get_pub78(nonprofit)
    bmf = get_bmf(nonprofit)
    ofac = get_ofac(nonprofit)

    print("\nIRS Publication 78")
    print(
        "  not returned"
        if pub78 is None
        else f"  listed: {pub78['verified']}, as of {pub78['most_recent']}"
    )

    print("\nIRS Business Master File")
    print(
        "  not returned"
        if bmf is None
        else f"  status: {bmf['status']}, subsection: {bmf['subsection_description']}"
    )

    print("\nOFAC")
    print("  not returned" if ofac is None else f"  {ofac['status']}")

    # A syntactically valid EIN and a clean set of findings are not an eligibility
    # decision. Apply your own grantmaking, compliance and risk policy.
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
