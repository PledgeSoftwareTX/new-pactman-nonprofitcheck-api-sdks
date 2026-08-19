"""
Bulk nonprofit check with local validation and result iteration.

Run:  PACTMAN_API_KEY=... python examples/bulk.py
"""

from __future__ import annotations

import os
import sys

from pactman_nonprofit_check_plus import (
    MAX_BULK_EINS,
    PactmanClient,
    PactmanValidationError,
    get_pub78,
)


def main() -> int:
    api_key = os.environ.get("PACTMAN_API_KEY")

    if not api_key:
        print("Set PACTMAN_API_KEY before running this example.", file=sys.stderr)
        return 1

    eins = ["41-1787097", "996589560"]
    print(f"Checking {len(eins)} EINs (server limit is {MAX_BULK_EINS} per request).")

    with PactmanClient(
        api_key=api_key, base_url=os.environ.get("PACTMAN_BASE_URL")
    ) as client:
        try:
            result = client.nonprofits.check_bulk(eins)
        except PactmanValidationError as error:
            # Nothing was sent — the whole batch is rejected before the request.
            print("Local validation failed, no request was sent:", file=sys.stderr)

            for issue in error.issues:
                print(f"  index {issue.index}: {issue.message}", file=sys.stderr)

            return 1

    print(f"\nMatched {len(result.organizations)} organizations.")

    for org in result.organizations:
        pub78 = get_pub78(org)
        listed = "n/a" if pub78 is None else pub78["verified"]
        print(f"  {org['ein']}  {org['organization_name']}  pub78_listed={listed}")

    # EINs with no record come back on a successful response, not as an error.
    if result.not_found_eins:
        print(f"\nNo record for: {', '.join(result.not_found_eins)}")

    print(f"\nChecks consumed: {result.check_count}")

    # Duplicates are sent as supplied, because each one consumes quota. Pass
    # dedupe=True to collapse them first.
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
