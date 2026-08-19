"""
EX-04 — Applicant name comparison.

An applicant types a name during onboarding. The API returns the name IRS
records hold, plus an alternate name when one exists. Punctuation, casing and
abbreviation differences are normal; they are not evidence of fraud.

The SDK deliberately has no ``names_match()``. What counts as a match is your
policy, so the comparison lives here, in customer code.

Run:  PACTMAN_API_KEY=... python examples/ex_04_name_comparison.py
"""

from __future__ import annotations

from lib.client import create_client
from lib.fixture_api import FIXTURE_EINS
from lib.matching import compare_name, is_agreement
from lib.print import bullet, field, heading, note, pick


def route_name_outcome(outcome: str) -> str:
    """Your routing policy, not the SDK's."""
    if outcome in ("exact", "normalized"):
        return "continue — the submitted name agrees with an IRS-held name"

    if outcome == "not_returned":
        return "manual review — the API returned no name to compare against"

    return "manual review — a human decides whether this is a rebrand, a typo, or the wrong EIN"


def main() -> int:
    ein = FIXTURE_EINS["public_charity"]

    # Three applicants against the same organization: a formatting difference, an
    # abbreviation difference, and a genuinely different name.
    applicants = [
        {"ein": ein, "legal_name": "Meals Today Example Nonprofit"},
        {"ein": ein, "legal_name": "meals today example nonprofit, inc."},
        {"ein": ein, "legal_name": "Springfield Animal Rescue"},
    ]

    with create_client() as client:
        for applicant in applicants:
            nonprofit = client.nonprofits.check(applicant["ein"]).nonprofit

            if nonprofit is None:
                print(f"No record for {applicant['ein']}.")
                continue

            comparison = compare_name(
                applicant["legal_name"],
                {
                    "organization_name": pick(nonprofit, "organization_name"),
                    "organization_name_aka": pick(nonprofit, "organization_name_aka"),
                },
            )

            heading(f"Applicant: {applicant['legal_name']}")
            field("organization_name", pick(nonprofit, "organization_name"))
            field("organization_name_aka", pick(nonprofit, "organization_name_aka"))
            field("normalized applicant", comparison.submitted)

            for candidate in comparison.candidates:
                bullet(f'{candidate.source} normalizes to "{candidate.normalized}"')

            field("outcome", comparison.outcome)
            field("matched field", comparison.matched_field)
            field("agreement", is_agreement(comparison.outcome))
            field("routed to", route_name_outcome(comparison.outcome))

    note(
        "A name mismatch is a reason to look, not a finding. Organizations rebrand, file\n"
        "under a parent, and appear in IRS data under a name no donor would recognize.\n"
        "This example routes disagreement to review; it never labels an applicant."
    )

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
