"""
EX-13 — Filing and exemption metadata.

Displays ``filing_req_code``, the exemption status, the ruling date and the
other IRS classification codes on the response.

Two rules apply to every code below:

- the raw value is preserved exactly as the API sent it, null included
- a code is only labelled through a documented table with an unknown-value
  fallback, so a value added by the IRS reads as "unrecognized", never as a
  blank and never as the wrong label

Run:  PACTMAN_API_KEY=... python examples/ex_13_filing_exemption_metadata.py
"""

from __future__ import annotations

from lib.fixture_api import FIXTURE_EINS, fixture_api
from lib.irs_codes import (
    CodeDescription,
    describe_exempt_status,
    describe_filing_requirement,
    describe_pf_filing_requirement,
    format_ruling_date,
)
from lib.print import field, heading, note, pick, render

from pactman_nonprofit_check_plus import get_bmf


def code_row(label: str, mapped: CodeDescription) -> None:
    known = str(mapped.known).ljust(6)
    print(
        f"  {label.ljust(28)} raw={render(mapped.code).ljust(10)}"
        f" known={known} {mapped.description or mapped.display}"
    )


def main() -> int:
    cases = [
        ("public charity", FIXTURE_EINS["public_charity"]),
        ("private foundation", FIXTURE_EINS["private_foundation"]),
        ("revoked — status code differs", FIXTURE_EINS["revoked"]),
        ("sparse — several codes are null", FIXTURE_EINS["sparse_identity"]),
    ]

    with fixture_api() as client:
        for label, ein in cases:
            nonprofit = client.nonprofits.check(ein).nonprofit

            if nonprofit is None:
                print(f"No record for {ein}.")
                continue

            bmf = get_bmf(nonprofit)

            heading(f"{label} — {nonprofit.get('organization_name')}")

            code_row(
                "filing_req_code",
                describe_filing_requirement(pick(bmf, "filing_req_code")),
            )
            code_row(
                "bmf_source_pf_filing_req_cd",
                describe_pf_filing_requirement(pick(bmf, "pf_filing_req_cd")),
            )
            code_row(
                "exempt_status_code",
                describe_exempt_status(pick(bmf, "exempt_status_code")),
            )

            # Codes the API already describes for you. Read the description it
            # sends; do not shadow it with a local table that will drift.
            field("bmf_subsection", pick(bmf, "subsection"))
            field("subsection_description", pick(bmf, "subsection_description"))
            field("foundation_code", pick(bmf, "foundation_code"))
            field("foundation_code_description", pick(bmf, "foundation_code_description"))

            field("ruling_month", pick(bmf, "ruling_month"))
            field("ruling_year", pick(bmf, "ruling_year"))
            field(
                "ruling date",
                format_ruling_date(pick(bmf, "ruling_month"), pick(bmf, "ruling_year")),
            )
            field("group_exemption", pick(bmf, "group_exemption"))
            field("revocation_code", pick(nonprofit, "revocation_code"))

        # An unknown code must survive the round trip intact. This is the case
        # that breaks applications which map codes eagerly into an enum.
        nonprofit = client.nonprofits.check(FIXTURE_EINS["future_fields"]).nonprofit

        heading("A code this SDK version has never seen")
        field("foundation_type_code", pick(nonprofit, "foundation_type_code"))
        field("foundation_type_description", pick(nonprofit, "foundation_type_description"))
        code_row("exempt_status_code (forced)", describe_exempt_status("99"))
        field("value preserved", pick(nonprofit, "foundation_type_code") == "zz")

    note(
        'Never coerce an unrecognized code to a default. "Unknown" is a real state and\n'
        "usually means review, not approval — see ex-25 for the same rule applied to\n"
        "whole fields the SDK does not know about yet."
    )

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
