"""
Local lookup tables for IRS codes the API returns without a description.

The API already describes most classifications for you — ``subsection_description``,
``foundation_code_description``, ``foundation_type_description``. Prefer those:
they come from the source and change with it. Only fields returned as a bare
code need a table, and a table you own is a table you have to maintain.

Two rules make that safe:

1. Every lookup has an unknown-value fallback that keeps the original code
   visible, so a value added by the IRS degrades to "code 42, meaning unknown to
   this application" rather than to a blank or a wrong label.
2. ``None`` is reported as null, never as an unknown code.

Verify these against the current IRS Exempt Organizations Business Master File
data dictionary and Publication 78 documentation before relying on them for a
policy decision.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any

from .print import NOT_RETURNED

FILING_REQUIREMENT = {
    "00": "No 990 return required",
    "01": "Form 990 or 990-EZ required",
    "02": "Form 990-N (e-Postcard) required",
    "03": "Group return",
    "04": "Form 990-BL required (black lung trust)",
    "06": "Not required to file (church)",
    "07": "Government 501(c)(1)",
    "13": "Not required to file (religious organization)",
    "14": "Not required to file (state instrumentality)",
}
"""IRS EO BMF ``FILING_REQ_CD`` — which annual return the organization files."""

PF_FILING_REQUIREMENT = {
    "0": "No 990-PF return required",
    "1": "Form 990-PF required",
}
"""IRS EO BMF ``PF_FILING_REQ_CD`` — whether a 990-PF is required."""

EXEMPT_STATUS = {
    "01": "Unconditional exemption",
    "02": "Conditional exemption",
    "12": "Trust described in section 4947(a)(2)",
    "25": "Organization terminated",
}
"""IRS EO BMF ``STATUS`` — the exemption status the BMF carries."""

DEDUCTIBILITY_STATUS = {
    "PC": "Public charity",
    "POF": "Private operating foundation",
    "PF": "Private foundation",
    "SO": "Supporting organization",
    "SOUNK": "Supporting organization, type not determined",
    "LODGE": "Domestic fraternal society",
    "FORGN": "Foreign organization",
    "GROUP": "Subordinate organization in a group ruling",
    "EO": "Exempt organization, other",
}
"""Publication 78 deductibility status codes."""


@dataclass(frozen=True)
class CodeDescription:
    code: Any
    known: bool
    description: str | None
    display: str


def _lookup(table: dict[str, str], code: Any, label: str) -> CodeDescription:
    if code is None or code is NOT_RETURNED:
        return CodeDescription(
            code=code,
            known=False,
            description=None,
            display="<null>" if code is None else "<not returned>",
        )

    description = table.get(code)

    if description is None:
        # A code this application has never seen. Keep it legible and keep it
        # flagged; do not guess, and do not drop it.
        return CodeDescription(
            code=code,
            known=False,
            description=None,
            display=f"{code} — unrecognized {label} code, not interpreted",
        )

    return CodeDescription(
        code=code, known=True, description=description, display=f"{code} — {description}"
    )


def describe_filing_requirement(code: Any) -> CodeDescription:
    return _lookup(FILING_REQUIREMENT, code, "filing requirement")


def describe_pf_filing_requirement(code: Any) -> CodeDescription:
    return _lookup(PF_FILING_REQUIREMENT, code, "private foundation filing requirement")


def describe_exempt_status(code: Any) -> CodeDescription:
    return _lookup(EXEMPT_STATUS, code, "exempt status")


def describe_deductibility_status(code: Any) -> CodeDescription:
    return _lookup(DEDUCTIBILITY_STATUS, code, "deductibility status")


def format_ruling_date(month: Any, year: Any) -> str:
    """``ruling_month`` + ``ruling_year`` as one value, without inventing a date."""
    if not year or year is NOT_RETURNED:
        return "<null>" if year is None else "<not returned>"

    return f"{year}-{str(month).zfill(2)}" if month and month is not NOT_RETURNED else str(year)
