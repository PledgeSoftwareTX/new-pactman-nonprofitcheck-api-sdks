"""
EX-02 — EIN normalization before a single check.

An EIN arrives from an onboarding form with a hyphen and stray whitespace. The
SDK normalizes it to nine digits before building the request URL; the original
input is kept locally so support can see exactly what the applicant typed.

Run:  PACTMAN_API_KEY=... python examples/ex_02_ein_normalization.py
"""

from __future__ import annotations

import json

from lib.client import create_client
from lib.fixture_api import FIXTURE_EINS
from lib.print import field, heading, note, pick

from pactman_nonprofit_check_plus import is_valid_ein, normalize_ein


def main() -> int:
    ein = FIXTURE_EINS["public_charity"]

    # What a form actually submits, versus what the endpoint expects.
    submitted = f"  {ein[:2]}-{ein[2:]}  "

    heading("Normalization")
    field("as submitted", json.dumps(submitted))
    field("is_valid_ein", is_valid_ein(submitted))
    field("normalized", normalize_ein(submitted))
    field("hyphenless input", normalize_ein(ein))

    # Both inputs address the same organization, so they are the same request.
    field("same request", normalize_ein(submitted) == normalize_ein(ein))

    # Keep the raw input alongside the normalized value for local diagnostics.
    # Store the normalized form as your key — that is what the API echoes back.
    applicant = {"ein_as_submitted": submitted, "ein": normalize_ein(submitted)}

    # `check` normalizes internally too, so passing the raw string is safe. Doing
    # it up front means your own records and the API's agree on one canonical value.
    with create_client() as client:
        result = client.nonprofits.check(applicant["ein_as_submitted"])

    heading("Response")
    field("EIN in request", applicant["ein"])
    field("EIN in response", pick(result.nonprofit, "ein"))
    field("organization_name", pick(result.nonprofit, "organization_name"))

    note(
        "Normalization is a formatting step. A nine-digit value is not evidence that an\n"
        "organization exists, is tax-exempt, or is in good standing."
    )

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
