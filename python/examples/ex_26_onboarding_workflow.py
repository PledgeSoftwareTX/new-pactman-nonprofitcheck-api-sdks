"""
EX-26 — Donation-platform onboarding workflow.

The end-to-end shape: an applicant supplies an EIN, a legal name and an address;
one check gathers BMF, Publication 78, revocation, OFAC, conflict and freshness
findings; the platform routes the applicant.

The routing rules below belong to this fictional platform. Read them as an
illustration of where your policy lives, not as a policy to adopt. The SDK
contributes evidence and stops there — it never produces the decision.

Run:  PACTMAN_API_KEY=... python examples/ex_26_onboarding_workflow.py
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Any

from lib.fixture_api import FIXTURE_EINS, fixture_api
from lib.matching import (
    NameComparison,
    compare_address_field,
    compare_name,
    is_agreement,
    normalize_address_line,
    normalize_zip,
)
from lib.print import bullet, field, heading, note, pick
from lib.screening import collect_findings, concerns

from pactman_nonprofit_check_plus import PactmanError

# This platform's rules, in one place, reviewable by its compliance team.
STALE_AFTER_DAYS = 120
REQUIRE_PUB78_LISTING = True
ADDRESS_COMPONENTS = ["address_line1", "city", "state", "zip"]

APPLICANT_ADDRESS = {
    "address_line1": "50 Lowell Ave",
    "city": "Westfield",
    "state": "MA",
    "zip": "01085",
}

APPLICANTS: list[dict[str, Any]] = [
    {
        "ein": FIXTURE_EINS["public_charity"],
        "legal_name": "Meals Today Example Nonprofit, Inc.",
        "address": APPLICANT_ADDRESS,
    },
    {
        "ein": FIXTURE_EINS["revoked"],
        "legal_name": "Lapsed Filings Example Society",
        "address": APPLICANT_ADDRESS,
    },
    {
        "ein": FIXTURE_EINS["ofac_match"],
        "legal_name": "Overseas Relief Example Fund",
        "address": APPLICANT_ADDRESS,
    },
    {
        "ein": FIXTURE_EINS["conflicted"],
        "legal_name": "Crosscheck Example Institute",
        "address": APPLICANT_ADDRESS,
    },
    {
        "ein": FIXTURE_EINS["no_record"],
        "legal_name": "Unlisted Example Org",
        "address": {
            "address_line1": "1 Main St",
            "city": "Boston",
            "state": "MA",
            "zip": "02108",
        },
    },
]


@dataclass(frozen=True)
class Decision:
    decision: str
    reasons: list[str]


def route(
    findings: dict[str, Any],
    name_comparison: NameComparison,
    address_outcomes: dict[str, str],
    issues: list[str],
) -> Decision:
    """Applies the policy to the gathered evidence. Returns a route and its reasons."""
    reasons = list(issues)

    if findings["revoked"] and not findings["reinstated"]:
        return Decision("reject", ["Exemption revoked with no reinstatement.", *reasons])

    if findings["ofac_state"] == "match":
        return Decision("reject", ["Possible OFAC SDN match.", *reasons])

    if not is_agreement(name_comparison.outcome):
        reasons.append(
            f"Submitted name did not match an IRS-held name ({name_comparison.outcome})."
        )

    address_conflicts = [
        component
        for component in ADDRESS_COMPONENTS
        if address_outcomes[component] == "mismatch"
    ]

    if address_conflicts:
        reasons.append(f"Address components disagree: {', '.join(address_conflicts)}.")

    if REQUIRE_PUB78_LISTING and findings["pub78_verified"] is not True:
        reasons.append("Not listed in Publication 78, which this platform requires.")

    if not reasons:
        return Decision("approve", ["Every check this platform requires was satisfied."])

    return Decision("manual_review", reasons)


def main() -> int:
    outcomes: list[dict[str, Any]] = []

    with fixture_api() as client:
        for applicant in APPLICANTS:
            heading(f"Applicant {applicant['ein']} — {applicant['legal_name']}")

            try:
                result = client.nonprofits.check(applicant["ein"])
            except PactmanError as error:
                # A failed lookup is not a rejection. Nothing was learned, so
                # nothing can be concluded — the applicant waits, they are not
                # turned away.
                field("lookup", f"failed: {type(error).__name__} ({error.category})")
                field("decision", "manual_review — the check could not be completed")
                outcomes.append({"ein": applicant["ein"], "decision": "manual_review"})
                continue

            nonprofit = result.nonprofit

            if nonprofit is None:
                field("decision", "manual_review — no record returned for this EIN")
                outcomes.append({"ein": applicant["ein"], "decision": "manual_review"})
                continue

            findings = collect_findings(nonprofit)
            issues = concerns(findings, stale_after_days=STALE_AFTER_DAYS)

            name_comparison = compare_name(
                applicant["legal_name"],
                {
                    "organization_name": pick(nonprofit, "organization_name"),
                    "organization_name_aka": pick(nonprofit, "organization_name_aka"),
                },
            )

            address_outcomes = {
                component: compare_address_field(
                    applicant["address"][component],
                    pick(nonprofit, component),
                    normalize_zip if component == "zip" else normalize_address_line,
                ).outcome
                for component in ADDRESS_COMPONENTS
            }

            field("IRS name", pick(nonprofit, "organization_name"))
            field("name comparison", name_comparison.outcome)
            field(
                "address comparison",
                " ".join(f"{key}={value}" for key, value in address_outcomes.items()),
            )
            field("bmf_status", findings["bmf_status"])
            field("pub78_verified", findings["pub78_verified"])
            field(
                "revoked / reinstated",
                f"{findings['revoked']} / {findings['reinstated']}",
            )
            field("ofac state", findings["ofac_state"])
            field("irs_bmf_pub78_conflict", findings["irs_bmf_pub78_conflict"])
            field("oldest source age (days)", findings["oldest_source_age_days"])

            decision = route(findings, name_comparison, address_outcomes, issues)

            field("decision", decision.decision)

            for reason in decision.reasons:
                bullet(reason)

            # The record that makes the decision explainable months later.
            outcomes.append(
                {
                    "ein": applicant["ein"],
                    "decision": decision.decision,
                    "reasons": decision.reasons,
                    "checked_at": datetime.now(timezone.utc).isoformat(),
                    "request_id": result.request_id,
                    "findings": findings,
                }
            )

    heading("Onboarding queue")

    for outcome in outcomes:
        print(f"  {outcome['ein']}  {outcome['decision']}")

    note(
        "The platform decided; the SDK did not. Nothing in this package returns approve,\n"
        "reject, eligible or safe, and no combination of the fields above constitutes a\n"
        "compliance determination on its own."
    )

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
