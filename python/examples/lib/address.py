"""
Structural validation of the address an API response carries.

None of this is part of the SDK, and deliberately so. The API reports the
address IRS records hold; deciding whether that address is good enough to act on
is a customer policy question.

What this answers: is the returned address *well-formed and self-consistent* —
are the components that matter present, is ``state`` a real USPS code, does
``state_name`` agree with it, is ``zip`` shaped like a ZIP and does it belong to
the state claimed alongside it.

What this does not answer: whether mail sent there arrives. Deliverability is a
question for USPS, Lob, Smarty or Google Address Validation, and it needs a
network call and a second credential. See :func:`validate_address` for where a
deliverability verdict would slot in.

Every check is conservative in the same direction: a check that cannot be run
reports ``not_checkable``, never ``fail``. An incomplete lookup table here must
not manufacture a finding about somebody's address.
"""

from __future__ import annotations

import re
from collections.abc import Mapping
from dataclasses import dataclass
from typing import Any

from .print import NOT_RETURNED, pick

US_STATES = {
    "AL": "Alabama",
    "AK": "Alaska",
    "AZ": "Arizona",
    "AR": "Arkansas",
    "CA": "California",
    "CO": "Colorado",
    "CT": "Connecticut",
    "DE": "Delaware",
    "DC": "District of Columbia",
    "FL": "Florida",
    "GA": "Georgia",
    "HI": "Hawaii",
    "ID": "Idaho",
    "IL": "Illinois",
    "IN": "Indiana",
    "IA": "Iowa",
    "KS": "Kansas",
    "KY": "Kentucky",
    "LA": "Louisiana",
    "ME": "Maine",
    "MD": "Maryland",
    "MA": "Massachusetts",
    "MI": "Michigan",
    "MN": "Minnesota",
    "MS": "Mississippi",
    "MO": "Missouri",
    "MT": "Montana",
    "NE": "Nebraska",
    "NV": "Nevada",
    "NH": "New Hampshire",
    "NJ": "New Jersey",
    "NM": "New Mexico",
    "NY": "New York",
    "NC": "North Carolina",
    "ND": "North Dakota",
    "OH": "Ohio",
    "OK": "Oklahoma",
    "OR": "Oregon",
    "PA": "Pennsylvania",
    "RI": "Rhode Island",
    "SC": "South Carolina",
    "SD": "South Dakota",
    "TN": "Tennessee",
    "TX": "Texas",
    "UT": "Utah",
    "VT": "Vermont",
    "VA": "Virginia",
    "WA": "Washington",
    "WV": "West Virginia",
    "WI": "Wisconsin",
    "WY": "Wyoming",
    # Territories and military posts. An exempt organization can hold any of these.
    "AS": "American Samoa",
    "GU": "Guam",
    "MP": "Northern Mariana Islands",
    "PR": "Puerto Rico",
    "VI": "Virgin Islands",
    "AA": "Armed Forces Americas",
    "AE": "Armed Forces Europe",
    "AP": "Armed Forces Pacific",
}
"""USPS codes and the state names the API pairs them with."""

ZIP_PREFIXES = {
    "AL": [(350, 369)],
    "AK": [(995, 999)],
    "AZ": [(850, 865)],
    "AR": [(716, 729)],
    "CA": [(900, 961)],
    "CO": [(800, 816)],
    "CT": [(60, 69)],
    "DE": [(197, 199)],
    "DC": [(200, 200), (202, 205), (569, 569)],
    "FL": [(320, 349)],
    "GA": [(300, 319), (398, 399)],
    "HI": [(967, 968)],
    "ID": [(832, 838)],
    "IL": [(600, 629)],
    "IN": [(460, 479)],
    "IA": [(500, 528)],
    "KS": [(660, 679)],
    "KY": [(400, 427)],
    "LA": [(700, 714)],
    "ME": [(39, 49)],
    "MD": [(206, 219)],
    "MA": [(10, 27), (55, 55)],
    "MI": [(480, 499)],
    "MN": [(550, 567)],
    "MS": [(386, 397)],
    "MO": [(630, 658)],
    "MT": [(590, 599)],
    "NE": [(680, 693)],
    "NV": [(889, 898)],
    "NH": [(30, 38)],
    "NJ": [(70, 89)],
    "NM": [(870, 884)],
    "NY": [(5, 5), (63, 63), (100, 149)],
    "NC": [(270, 289)],
    "ND": [(580, 588)],
    "OH": [(430, 459)],
    "OK": [(730, 731), (734, 749)],
    "OR": [(970, 979)],
    "PA": [(150, 196)],
    "RI": [(28, 29)],
    "SC": [(290, 299)],
    "SD": [(570, 577)],
    "TN": [(370, 385)],
    # 733 is Austin, inside Oklahoma's run — the IRS's own service centre sits there.
    "TX": [(733, 733), (750, 799), (885, 885)],
    "UT": [(840, 847)],
    "VT": [(50, 59)],
    "VA": [(201, 201), (220, 246)],
    "WA": [(980, 994)],
    "WV": [(247, 268)],
    "WI": [(530, 549)],
    "WY": [(820, 831)],
    "AS": [(967, 967)],
    "GU": [(969, 969)],
    "MP": [(969, 969)],
    "PR": [(6, 9)],
    "VI": [(8, 8)],
    "AA": [(340, 340)],
    "AE": [(90, 98)],
    "AP": [(962, 966)],
}
"""
Leading three ZIP digits each state uses, as inclusive ranges.

Illustrative, not the USPS product. A prefix this table does not list makes the
ZIP-to-state check ``not_checkable``, so omissions cost coverage rather than
producing a false finding. Prefixes claimed by more than one state — 06390 on
Fishers Island is New York inside Connecticut's range, 340 is a military post
inside Florida's — pass for any of their claimants.
"""


def _prefix_owners() -> dict[int, set[str]]:
    """Prefix → every state that claims it, built once from the ranges above."""
    owners: dict[int, set[str]] = {}

    for state, ranges in ZIP_PREFIXES.items():
        for low, high in ranges:
            for prefix in range(low, high + 1):
                owners.setdefault(prefix, set()).add(state)

    return owners


PREFIX_OWNERS = _prefix_owners()

PLACEHOLDERS = {
    "N/A",
    "NA",
    "N A",
    "NONE",
    "NULL",
    "NIL",
    "UNKNOWN",
    "UNK",
    "TBD",
    "NOT AVAILABLE",
    "NOT APPLICABLE",
    "NO ADDRESS",
    "SAME",
    "SEE ATTACHED",
    "-",
    "--",
    ".",
    "...",
    "X",
    "XX",
    "XXX",
    "XXXX",
    "0",
    "00",
    "000",
}
"""
Values that occupy a field without saying anything.

These arrive in real IRS extracts. Left unchecked they read as data: a ``city``
of ``UNKNOWN`` is present, is a string, and is not ``None``.
"""

NUMBERLESS_LINES = {"GENERAL DELIVERY", "PO BOX", "POST OFFICE BOX"}
"""Street lines that legitimately carry no house number."""

REQUIRED_COMPONENTS = ["address_line1", "city", "state", "zip"]
"""Components an address needs before it locates anything."""

ADDRESS_COMPONENTS = [
    "address_line1",
    "address_line2",
    "city",
    "state",
    "state_name",
    "zip",
]
"""Every component this module looks at, required or not."""

_NON_ALPHANUMERIC = re.compile(r"[^A-Z0-9]+")


def _is_absent(value: Any) -> bool:
    return value is None or value is NOT_RETURNED or str(value).strip() == ""


def _squash(value: Any) -> str:
    return _NON_ALPHANUMERIC.sub(" ", str(value).upper()).strip()


def is_placeholder(value: Any) -> bool:
    """True when a value is present but carries no information."""
    if _is_absent(value):
        return False

    text = str(value).strip().upper()

    return text in PLACEHOLDERS or _squash(text) in PLACEHOLDERS


def zip5(value: Any) -> str | None:
    """The five-digit prefix of a ZIP, or ``None`` when there is nothing to read."""
    if _is_absent(value):
        return None

    digits = re.sub(r"\D", "", str(value))

    return digits[:5] if len(digits) >= 5 else None


def states_for_zip(value: Any) -> set[str] | None:
    """``{"ME"}`` for ``04856``, ``None`` when no state claims the prefix."""
    five = zip5(value)

    if five is None:
        return None

    return PREFIX_OWNERS.get(int(five[:3]))


@dataclass(frozen=True)
class Check:
    id: str
    label: str
    outcome: str
    """``pass`` | ``fail`` | ``not_checkable``."""

    detail: str | None = None


@dataclass(frozen=True)
class AddressValidation:
    verdict: str
    """``usable`` | ``incomplete`` | ``inconsistent``."""

    checks: list[Check]
    missing: list[str]
    failures: list[Check]


def validate_address(record: Mapping[str, Any] | None) -> AddressValidation:
    """
    Runs every structural check against one returned address.

    ``record`` is anything carrying the six address fields — a ``nonprofit`` from
    ``client.nonprofits.check()`` reads directly.

    The verdict is ``inconsistent`` when a check failed, ``incomplete`` when a
    required component was not returned, and ``usable`` when neither happened. It
    is never ``deliverable``: nothing here has asked USPS anything.
    """

    def value(component: str) -> Any:
        return pick(record, component)

    checks: list[Check] = []

    # 1. Presence. A component the API did not return has not been confirmed by
    #    anything, which is the same lesson the comparison examples teach.
    missing = [name for name in REQUIRED_COMPONENTS if _is_absent(value(name))]

    checks.append(
        Check(
            "required_components",
            "required components present",
            "pass" if not missing else "fail",
            ", ".join(REQUIRED_COMPONENTS)
            if not missing
            else f"not returned: {', '.join(missing)}",
        )
    )

    # 2. Placeholders. Present, and still empty of meaning.
    placeholders = [name for name in ADDRESS_COMPONENTS if is_placeholder(value(name))]

    checks.append(
        Check(
            "no_placeholders",
            "no placeholder values",
            "pass" if not placeholders else "fail",
            None
            if not placeholders
            else ", ".join(f'{name}="{value(name)}"' for name in placeholders),
        )
    )

    # 3. The state code itself.
    state = None if _is_absent(value("state")) else str(value("state")).strip().upper()

    if state is None:
        checks.append(
            Check(
                "state_code", "state is a USPS code", "not_checkable", "state was not returned"
            )
        )
    elif state in US_STATES:
        checks.append(
            Check("state_code", "state is a USPS code", "pass", f"{state} — {US_STATES[state]}")
        )
    else:
        checks.append(
            Check(
                "state_code",
                "state is a USPS code",
                "fail",
                f'"{value("state")}" is not a USPS code',
            )
        )

    # 4. state_name against state. Two fields for one fact is two chances to be
    #    wrong, and IRS extracts do disagree with themselves.
    state_name = None if _is_absent(value("state_name")) else str(value("state_name")).strip()
    expected_name = None if state is None else US_STATES.get(state)

    if state_name is None or expected_name is None:
        checks.append(
            Check(
                "state_name_agrees",
                "state_name agrees with state",
                "not_checkable",
                "state_name was not returned"
                if state_name is None
                else "state is not a known code",
            )
        )
    elif _squash(state_name) == _squash(expected_name):
        checks.append(
            Check("state_name_agrees", "state_name agrees with state", "pass", state_name)
        )
    else:
        checks.append(
            Check(
                "state_name_agrees",
                "state_name agrees with state",
                "fail",
                f'state={state} implies "{expected_name}", state_name says "{state_name}"',
            )
        )

    # 5. ZIP shape. Five digits, or nine for ZIP+4. Anything else is not a ZIP.
    raw_zip = None if _is_absent(value("zip")) else str(value("zip")).strip()
    zip_digits = "" if raw_zip is None else re.sub(r"\D", "", raw_zip)

    if raw_zip is None:
        checks.append(
            Check("zip_format", "zip is 5 or 9 digits", "not_checkable", "zip was not returned")
        )
    elif len(zip_digits) in (5, 9):
        checks.append(Check("zip_format", "zip is 5 or 9 digits", "pass", raw_zip))
    else:
        checks.append(
            Check(
                "zip_format",
                "zip is 5 or 9 digits",
                "fail",
                f'"{raw_zip}" has {len(zip_digits)} digits',
            )
        )

    # 6. ZIP against state. The check that catches a transcription error no
    #    single-field check can see.
    claimants = states_for_zip(raw_zip)
    five = zip5(raw_zip)

    if raw_zip is None or state is None:
        checks.append(
            Check(
                "zip_matches_state",
                "zip belongs to state",
                "not_checkable",
                "zip or state was not returned",
            )
        )
    elif claimants is None:
        checks.append(
            Check(
                "zip_matches_state",
                "zip belongs to state",
                "not_checkable",
                f"no state is on file for prefix {five[:3] if five else '???'}",
            )
        )
    elif state in claimants:
        checks.append(
            Check(
                "zip_matches_state", "zip belongs to state", "pass", f"{five} is a {state} ZIP"
            )
        )
    else:
        checks.append(
            Check(
                "zip_matches_state",
                "zip belongs to state",
                "fail",
                f"{five} belongs to {'/'.join(sorted(claimants))}, state says {state}",
            )
        )

    # 7. The street line. A number, a box, or general delivery.
    line1 = None if _is_absent(value("address_line1")) else _squash(value("address_line1"))

    if line1 is None:
        checks.append(
            Check(
                "line1_shape",
                "address_line1 locates a delivery point",
                "not_checkable",
                "address_line1 was not returned",
            )
        )
    elif re.search(r"\d", line1) or line1 in NUMBERLESS_LINES:
        checks.append(
            Check(
                "line1_shape",
                "address_line1 locates a delivery point",
                "pass",
                str(value("address_line1")),
            )
        )
    else:
        checks.append(
            Check(
                "line1_shape",
                "address_line1 locates a delivery point",
                "fail",
                f'"{value("address_line1")}" carries no number, box or general-delivery marker',
            )
        )

    failures = [entry for entry in checks if entry.outcome == "fail"]

    # A deliverability verdict from USPS or an equivalent would be folded in
    # here, as one more check. Nothing above has left the process.
    if any(entry.id != "required_components" for entry in failures):
        verdict = "inconsistent"
    elif missing:
        verdict = "incomplete"
    else:
        verdict = "usable"

    return AddressValidation(verdict, checks, missing, failures)


def is_usable(verdict: str) -> bool:
    """True for the one verdict that clears an address for automated use."""
    return verdict == "usable"
