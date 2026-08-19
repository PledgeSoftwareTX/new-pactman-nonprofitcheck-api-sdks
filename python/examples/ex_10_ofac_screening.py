"""
EX-10 — OFAC screening result.

The API reports OFAC as a sentence, not a flag. Four results have to stay
distinguishable, because they route to four different places::

    no_match     the organization was screened and was not on the SDN list
    match        a close match was found — never auto-clear this
    null         the field was returned with no value
    unavailable  no OFAC field was returned at all; nothing was screened

The SDK exposes no ``has_ofac_match`` boolean. Deriving one means
pattern-matching English that the source can reword at any time, and a screening
step that silently starts returning "no match" because a sentence changed is
worse than no screening step.

Run:  PACTMAN_API_KEY=... python examples/ex_10_ofac_screening.py
"""

from __future__ import annotations

import re
from dataclasses import dataclass
from typing import Any

from lib.fixture_api import FIXTURE_EINS, fixture_api
from lib.print import NOT_RETURNED, field, heading, note, pick

from pactman_nonprofit_check_plus import Nonprofit, get_ofac

_UID = re.compile(r"UID:", re.IGNORECASE)
_NOT_INCLUDED = re.compile(r"NOT included", re.IGNORECASE)

# Four states, four destinations. None of them is "approve automatically".
ROUTING = {
    "no_match": "continue — screened against the SDN list with no match",
    "match": "block and escalate to compliance — a possible SDN match must be adjudicated",
    "null": "hold — the field was returned empty; treat as unscreened, not as cleared",
    "unavailable": "hold — no OFAC data was returned; nothing was screened",
    "needs_review": "hold — the status text was not recognized by this application",
}


@dataclass(frozen=True)
class OfacFinding:
    state: str
    status: Any
    published_date: Any


def classify_ofac(nonprofit: Nonprofit) -> OfacFinding:
    """
    Classifies the OFAC finding into the four states above.

    The one textual test here is for the SDN unique identifier the API includes
    on a match. It is treated as a signal to escalate, never as a signal to
    clear: anything unrecognized falls through to ``needs_review``.
    """
    ofac = get_ofac(nonprofit)

    if ofac is None:
        return OfacFinding("unavailable", NOT_RETURNED, NOT_RETURNED)

    status = pick(ofac, "status")
    published_date = pick(ofac, "list_published_date")

    if status is None or status is NOT_RETURNED:
        return OfacFinding("null", status, published_date)

    if _UID.search(str(status)):
        return OfacFinding("match", status, published_date)

    if _NOT_INCLUDED.search(str(status)):
        return OfacFinding("no_match", status, published_date)

    return OfacFinding("needs_review", status, published_date)


def main() -> int:
    cases = [
        ("no match", FIXTURE_EINS["public_charity"]),
        ("possible match", FIXTURE_EINS["ofac_match"]),
        ("null status", FIXTURE_EINS["ofac_unavailable"]),
        ("source not returned", FIXTURE_EINS["sparse_identity"]),
    ]

    with fixture_api() as client:
        for label, ein in cases:
            nonprofit = client.nonprofits.check(ein).nonprofit

            if nonprofit is None:
                print(f"No record for {ein}.")
                continue

            finding = classify_ofac(nonprofit)

            heading(f"{label} — {nonprofit.get('organization_name')}")
            field("ofac_status", finding.status)
            field("ofac_list_published_date", finding.published_date)
            field(
                "get_ofac() returned",
                "None (no OFAC fields)" if get_ofac(nonprofit) is None else "a dict",
            )
            field("state", finding.state)
            field("routed to", ROUTING[finding.state])

    note(
        'Today the API substitutes the "NOT included" sentence when it has no OFAC value,\n'
        "so the null and unavailable branches are defensive. They still belong in your\n"
        "code: an absent screening result must never arrive at your approve path.\n\n"
        "A no-match result is a screening outcome from one list on one date. It is not\n"
        "sanctions clearance, and it does not cover any other watchlist you are obliged\n"
        "to check."
    )

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
