"""
Shared screening helpers for the workflow examples (ex-26 to ex-30).

These functions gather what the API said into one object. They do not decide
anything: there is no ``approved``, no ``eligible``, no ``safe``. Each workflow
applies its own policy to this evidence, and the policies differ on purpose — a
donation platform, a DAF and a payout gate reach different conclusions from
identical data, and all three are right for their own obligations.
"""

from __future__ import annotations

import re
from datetime import datetime
from typing import Any

from pactman_nonprofit_check_plus import Nonprofit, get_aroe, get_bmf, get_ofac, get_pub78

from .print import NOT_RETURNED, pick

_UID = re.compile(r"UID:", re.IGNORECASE)
_NOT_INCLUDED = re.compile(r"NOT included", re.IGNORECASE)

_DATE_FORMATS = (
    "%m/%d/%Y %I:%M:%S %p",
    "%m/%d/%Y",
    "%Y-%m-%dT%H:%M:%S",
    "%Y-%m-%d",
)


def ofac_state(nonprofit: Nonprofit) -> str:
    """The four OFAC states from ex-10. ``unavailable`` is never a pass."""
    ofac = get_ofac(nonprofit)

    if ofac is None:
        return "unavailable"

    status = pick(ofac, "status")

    if status is None or status is NOT_RETURNED:
        return "null"

    if _UID.search(str(status)):
        return "match"

    return "no_match" if _NOT_INCLUDED.search(str(status)) else "unrecognized"


def parse_api_date(value: Any) -> datetime | None:
    """The API formats dates as ``M/DD/YYYY h:mm:ss AM``. Unparseable is None."""
    if not value or value is NOT_RETURNED:
        return None

    text = str(value).strip()

    for pattern in _DATE_FORMATS:
        try:
            return datetime.strptime(text, pattern)
        except ValueError:
            continue

    return None


def oldest_source_age_days(nonprofit: Nonprofit, now: datetime | None = None) -> int | None:
    """Age in days of the oldest source date on the record, or None if undatable."""
    reference = now or datetime.now()

    dates = [
        parsed
        for parsed in (
            parse_api_date(nonprofit.get("most_recent_bmf")),
            parse_api_date(nonprofit.get("most_recent_pub78")),
            parse_api_date(nonprofit.get("ofac_list_published_date")),
            parse_api_date(nonprofit.get("aroe_list_published_date")),
            parse_api_date(nonprofit.get("organization_info_last_modified")),
        )
        if parsed is not None
    ]

    if not dates:
        return None

    return round((reference - min(dates)).total_seconds() / 86_400)


def collect_findings(nonprofit: Nonprofit, now: datetime | None = None) -> dict[str, Any]:
    """
    A flat, comparable view of the findings — every value copied from the response.

    ``None`` means the API returned null; :data:`NOT_RETURNED` means it returned
    no such field. Both are preserved so a consumer can tell them apart.
    """
    bmf = get_bmf(nonprofit)
    pub78 = get_pub78(nonprofit)
    aroe = get_aroe(nonprofit)

    organization_types = pick(pub78, "organization_types")
    limitations = [
        entry.get("deductibility_limitation")
        for entry in (organization_types or [])
        if isinstance(entry, dict) and entry.get("deductibility_limitation")
    ]

    revocation_code = pick(aroe, "revocation_code")
    revocation_date = pick(aroe, "revocation_date")
    reinstatement_date = pick(aroe, "reinstatement_date")

    return {
        "ein": pick(nonprofit, "ein"),
        "organization_name": pick(nonprofit, "organization_name"),
        "organization_name_aka": pick(nonprofit, "organization_name_aka"),
        "bmf_returned": bmf is not None,
        "bmf_status": pick(bmf, "status"),
        "exempt_status_code": pick(bmf, "exempt_status_code"),
        "subsection_description": pick(bmf, "subsection_description"),
        "foundation_type_code": pick(bmf, "foundation_type_code"),
        "foundation_type_description": pick(bmf, "foundation_type_description"),
        "pub78_returned": pub78 is not None,
        "pub78_verified": pick(pub78, "verified"),
        "deductibility_limitations": limitations,
        "revocation_code": revocation_code,
        "revocation_date": revocation_date,
        "reinstatement_date": reinstatement_date,
        "revoked": bool(revocation_code) or bool(revocation_date),
        "reinstated": bool(reinstatement_date),
        "ofac_state": ofac_state(nonprofit),
        "ofac_status": pick(nonprofit, "ofac_status"),
        "irs_bmf_pub78_conflict": pick(nonprofit, "irs_bmf_pub78_conflict"),
        "report_date": pick(nonprofit, "report_date"),
        "organization_info_last_modified": pick(nonprofit, "organization_info_last_modified"),
        "oldest_source_age_days": oldest_source_age_days(nonprofit, now),
    }


def concerns(findings: dict[str, Any], stale_after_days: int = 120) -> list[str]:
    """Human-readable reasons a workflow might want to stop. No verdict attached."""
    found: list[str] = []

    if findings["revoked"] and not findings["reinstated"]:
        found.append("listed in the IRS Automatic Revocation data with no reinstatement")

    if findings["revoked"] and findings["reinstated"]:
        found.append("revoked and later reinstated — the lapse period may still matter")

    if findings["ofac_state"] == "match":
        found.append("a possible OFAC SDN match was reported")

    if findings["ofac_state"] not in ("no_match", "match"):
        found.append(f"OFAC screening result is {findings['ofac_state']} — nothing was cleared")

    if findings["irs_bmf_pub78_conflict"] is True:
        found.append("the BMF and Publication 78 disagree about this organization")

    if findings["bmf_status"] is False:
        found.append("the BMF does not show the organization as exempt")

    if findings["pub78_verified"] is False:
        found.append("the organization is not listed in Publication 78")

    if not findings["bmf_returned"]:
        found.append("no BMF data was returned")

    if not findings["pub78_returned"]:
        found.append("no Publication 78 data was returned")

    age = findings["oldest_source_age_days"]

    if age is None:
        found.append("no source date was returned, so data age cannot be established")
    elif age > stale_after_days:
        found.append(f"the oldest source is {age} days old")

    return found


MATERIAL_FIELDS = [
    "organization_name",
    "bmf_status",
    "exempt_status_code",
    "pub78_verified",
    "revocation_code",
    "revocation_date",
    "reinstatement_date",
    "ofac_state",
    "irs_bmf_pub78_conflict",
    "foundation_type_code",
    "subsection_description",
]
"""Fields worth diffing between two checks of the same organization."""


def diff_findings(
    previous: dict[str, Any] | None,
    current: dict[str, Any] | None,
    fields: list[str] | None = None,
) -> list[dict[str, Any]]:
    """Changes between a stored set of findings and a fresh one."""
    changes: list[dict[str, Any]] = []

    for key in fields or MATERIAL_FIELDS:
        before = pick(previous, key)
        after = pick(current, key)

        if before != after:
            changes.append({"field": key, "before": before, "after": after})

    return changes
