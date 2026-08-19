"""
EX-11 — Cross-source conflict or inconsistency.

``irs_bmf_pub78_conflict`` is true when the Business Master File and Publication
78 disagree about an organization. The API reports the disagreement instead of
resolving it, and so does this example: it records what each source said and
creates a review outcome.

Silently preferring one source is the failure mode here. Whichever you pick, you
will be wrong for some organization, and you will have destroyed the evidence
that would have shown it.

Run:  PACTMAN_API_KEY=... python examples/ex_11_source_conflict.py
"""

from __future__ import annotations

import json
from collections.abc import Callable
from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Any

from lib.fixture_api import FIXTURE_EINS, fixture_api
from lib.matching import normalize_name
from lib.print import NOT_RETURNED, bullet, field, heading, note, pick, render

from pactman_nonprofit_check_plus import Nonprofit, get_aroe, get_bmf, get_ofac, get_pub78


def loosely(value: Any) -> str:
    """Case and punctuation differences are not disagreements. See ex-04."""
    return str(value).upper().strip()


@dataclass(frozen=True)
class CrossSourcePair:
    label: str
    bmf: str
    pub78: str
    normalize: Callable[[Any], Any]


CROSS_SOURCE_PAIRS = [
    CrossSourcePair(
        "organization name", "organization_name", "organization_name", normalize_name
    ),
    CrossSourcePair("EIN", "ein", "ein", loosely),
    CrossSourcePair("city", "city", "city", loosely),
    CrossSourcePair("state", "state", "state", loosely),
]
"""Fields the two IRS sources both report, so disagreement is visible per pair."""


def collect_conflicts(nonprofit: Nonprofit) -> list[dict[str, str]]:
    bmf = get_bmf(nonprofit)
    pub78 = get_pub78(nonprofit)
    findings: list[dict[str, str]] = []

    # The flag the API sets. This is the authoritative signal; the per-field
    # comparison below only explains it.
    if pick(nonprofit, "irs_bmf_pub78_conflict") is True:
        findings.append(
            {
                "field": "irs_bmf_pub78_conflict",
                "detail": "The API flagged a BMF / Publication 78 disagreement.",
            }
        )

    bmf_status = pick(bmf, "status")
    pub78_verified = pick(pub78, "verified")

    if bmf_status is True and pub78_verified is False:
        findings.append(
            {
                "field": "bmf_status vs pub78_verified",
                "detail": (
                    "The BMF lists the organization as exempt; Publication 78 "
                    "does not list it."
                ),
            }
        )

    if bmf_status is False and pub78_verified is True:
        findings.append(
            {
                "field": "bmf_status vs pub78_verified",
                "detail": (
                    "Publication 78 lists the organization; the BMF does not "
                    "show it as exempt."
                ),
            }
        )

    for pair in CROSS_SOURCE_PAIRS:
        bmf_value = pick(bmf, pair.bmf)
        pub78_value = pick(pub78, pair.pub78)

        # Only compare when both sources actually supplied a value. A field one
        # source omitted is missing data, not a conflict.
        if bmf_value in (None, NOT_RETURNED) or pub78_value in (None, NOT_RETURNED):
            continue

        if pair.normalize(bmf_value) != pair.normalize(pub78_value):
            findings.append(
                {
                    "field": pair.label,
                    "detail": f'BMF "{bmf_value}" vs Publication 78 "{pub78_value}"',
                }
            )

    return findings


def main() -> int:
    with fixture_api() as client:
        for ein in (FIXTURE_EINS["conflicted"], FIXTURE_EINS["public_charity"]):
            result = client.nonprofits.check(ein)
            nonprofit = result.nonprofit

            if nonprofit is None:
                print(f"No record for {ein}.")
                continue

            conflicts = collect_conflicts(nonprofit)

            heading(f"{nonprofit.get('organization_name')} ({nonprofit.get('ein')})")
            field("irs_bmf_pub78_conflict", pick(nonprofit, "irs_bmf_pub78_conflict"))
            field("conflicting signals", len(conflicts))

            for conflict in conflicts:
                bullet(f"{conflict['field']}: {conflict['detail']}")

            if not conflicts:
                bullet("sources agree on every field both of them returned")

            # Nothing is chosen. Both sides are kept, side by side, for the reviewer.
            bmf = get_bmf(nonprofit)
            pub78 = get_pub78(nonprofit)

            print("\n  source-by-source view:")
            print(f"    {'field'.ljust(20)} {'BMF'.ljust(30)} Publication 78")

            for pair in CROSS_SOURCE_PAIRS:
                left = render(pick(bmf, pair.bmf)).ljust(30)
                print(f"    {pair.label.ljust(20)} {left} {render(pick(pub78, pair.pub78))}")

            exempt = render(pick(bmf, "status")).ljust(30)
            print(f"    {'exempt/listed'.ljust(20)} {exempt} {render(pick(pub78, 'verified'))}")

            outcome = "manual_review" if conflicts else "continue"

            field("\npolicy outcome", outcome)

            if outcome == "manual_review":
                review_record = {
                    "ein": nonprofit.get("ein"),
                    "request_id": result.request_id,
                    "checked_at": datetime.now(timezone.utc).isoformat(),
                    "report_date": nonprofit.get("report_date"),
                    "conflicts": conflicts,
                    "sources": {
                        "bmf": bmf,
                        "pub78": pub78,
                        "aroe": get_aroe(nonprofit),
                        "ofac": get_ofac(nonprofit),
                    },
                }

                size = len(json.dumps(review_record))
                print(f"    review record: {size} bytes retained")
                print(
                    "    conflicting fields: "
                    + ", ".join(item["field"] for item in conflicts)
                )

    note(
        "A conflict is a fact about the data, not a fact about the organization. Record\n"
        "both sources, escalate, and let a person decide which one governs your workflow."
    )

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
