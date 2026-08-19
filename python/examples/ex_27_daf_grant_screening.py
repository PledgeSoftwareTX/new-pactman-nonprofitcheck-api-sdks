"""
EX-27 — DAF grant-recommendation screening.

A donor recommends a grant. Before the recommendation advances, the sponsoring
organization screens the grantee, shows the tax and foundation classification to
the grants team, and sends anything revoked, sanctioned, conflicting or ambiguous
to review.

A DAF's rules are stricter than a donation platform's — compare the policy block
here with the one in ex-26. Same API data, different obligations, different
outcomes. That difference is precisely why the SDK does not decide.

Run:  PACTMAN_API_KEY=... python examples/ex_27_daf_grant_screening.py
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Any

from lib.fixture_api import FIXTURE_EINS, fixture_api
from lib.print import bullet, field, heading, note
from lib.screening import collect_findings, concerns

# This sponsoring organization's rules. Yours will differ.
STALE_AFTER_DAYS = 90
# A private foundation grantee is not refused — it takes a different path,
# because expenditure responsibility applies.
PRIVATE_FOUNDATION_REQUIRES_EXPENDITURE_RESPONSIBILITY = True
# Anything the screen could not establish stops the recommendation.
TREAT_UNKNOWN_AS_BLOCKING = True

RECOMMENDATIONS: list[dict[str, Any]] = [
    {
        "grant_id": "G-1001",
        "ein": FIXTURE_EINS["public_charity"],
        "amount": 25_000,
        "donor": "Fund 88",
    },
    {
        "grant_id": "G-1002",
        "ein": FIXTURE_EINS["private_foundation"],
        "amount": 10_000,
        "donor": "Fund 88",
    },
    {
        "grant_id": "G-1003",
        "ein": FIXTURE_EINS["revoked"],
        "amount": 5_000,
        "donor": "Fund 14",
    },
    {
        "grant_id": "G-1004",
        "ein": FIXTURE_EINS["ofac_match"],
        "amount": 40_000,
        "donor": "Fund 14",
    },
    {
        "grant_id": "G-1005",
        "ein": FIXTURE_EINS["conflicted"],
        "amount": 7_500,
        "donor": "Fund 03",
    },
    {
        "grant_id": "G-1006",
        "ein": FIXTURE_EINS["reinstated"],
        "amount": 15_000,
        "donor": "Fund 03",
    },
    {
        "grant_id": "G-1007",
        "ein": FIXTURE_EINS["sparse_identity"],
        "amount": 2_000,
        "donor": "Fund 21",
    },
]


@dataclass(frozen=True)
class Screened:
    outcome: str
    queue: str
    issues: list[str]


def screen(findings: dict[str, Any]) -> Screened:
    issues = concerns(findings, stale_after_days=STALE_AFTER_DAYS)

    if findings["ofac_state"] == "match":
        return Screened("blocked", "sanctions_review", issues)

    if findings["revoked"] and not findings["reinstated"]:
        return Screened("blocked", "tax_status_review", issues)

    if findings["irs_bmf_pub78_conflict"] is True:
        return Screened("held", "source_conflict_review", issues)

    if TREAT_UNKNOWN_AS_BLOCKING and issues:
        return Screened("held", "grants_review", issues)

    is_private_foundation = findings["foundation_type_code"] == "pf"

    if is_private_foundation and PRIVATE_FOUNDATION_REQUIRES_EXPENDITURE_RESPONSIBILITY:
        return Screened("held", "expenditure_responsibility", issues)

    return Screened("advanced", "ready_for_approval", issues)


def main() -> int:
    with fixture_api() as client:
        # One bulk call for the whole recommendation batch.
        result = client.nonprofits.check_bulk(
            [entry["ein"] for entry in RECOMMENDATIONS]
        )

    by_ein = {org.get("ein"): org for org in result.organizations}

    heading("Screening batch")
    field("recommendations", len(RECOMMENDATIONS))
    field("records returned", len(result.organizations))
    field("no record for", ", ".join(result.not_found_eins) or "<none>")
    field("checks used this cycle", result.check_count)

    decisions: list[dict[str, Any]] = []

    for recommendation in RECOMMENDATIONS:
        nonprofit = by_ein.get(recommendation["ein"])

        heading(
            f"{recommendation['grant_id']} — ${recommendation['amount']:,}"
            f" to {recommendation['ein']}"
        )

        if nonprofit is None:
            field("outcome", "held")
            field("queue", "grants_review")
            bullet("No record was returned for this EIN. Nothing was verified.")
            decisions.append({**recommendation, "outcome": "held", "queue": "grants_review"})
            continue

        findings = collect_findings(nonprofit)
        screened = screen(findings)

        # What the grants team sees on screen.
        field("grantee", findings["organization_name"])
        field("also known as", findings["organization_name_aka"])
        field("subsection", findings["subsection_description"])
        field("foundation type", findings["foundation_type_description"])
        field("foundation type code", findings["foundation_type_code"])
        field(
            "deductibility limitations",
            ", ".join(findings["deductibility_limitations"]) or "<none>",
        )
        field("bmf_status", findings["bmf_status"])
        field("pub78_verified", findings["pub78_verified"])
        field("revocation_date", findings["revocation_date"])
        field("reinstatement_date", findings["reinstatement_date"])
        field("ofac state", findings["ofac_state"])
        field("conflict flag", findings["irs_bmf_pub78_conflict"])
        field("oldest source (days)", findings["oldest_source_age_days"])

        field("outcome", screened.outcome)
        field("queue", screened.queue)

        for issue in screened.issues:
            bullet(issue)

        decisions.append(
            {
                **recommendation,
                "outcome": screened.outcome,
                "queue": screened.queue,
                "screened_at": datetime.now(timezone.utc).isoformat(),
                "request_id": result.request_id,
                "source_findings": findings,
            }
        )

    heading("Recommendation queue")

    for decision in decisions:
        outcome = decision["outcome"].ljust(9)
        print(f"  {decision['grant_id']}  {decision['ein']}  {outcome} → {decision['queue']}")

    advanced = [decision for decision in decisions if decision["outcome"] == "advanced"]

    field("\nadvanced to approval", len(advanced))
    field("held or blocked", len(decisions) - len(advanced))

    note(
        "Advancing a recommendation is a step in this DAF's process, not a legal approval\n"
        "of the grant. The findings recorded above are the source data the decision\n"
        "rested on; the determination itself remains the sponsoring organization's."
    )

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
