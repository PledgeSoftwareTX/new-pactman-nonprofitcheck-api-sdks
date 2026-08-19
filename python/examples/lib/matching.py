"""
Name and address comparison for the onboarding examples.

None of this is part of the SDK, and deliberately so. The API returns the
identity IRS records hold; deciding whether "St. Mary's Hosp" and "SAINT MARYS
HOSPITAL INC" are the same applicant is a customer policy question, and the
answer differs between a donation platform, a DAF and a payroll-giving system.

The comparisons below are conservative on purpose:

- punctuation, casing, spacing and common abbreviations are not differences
- a value the API did not return is never scored as agreement
- the outcome is a routing hint, never a fraud finding
"""

from __future__ import annotations

import re
from collections.abc import Callable, Mapping
from dataclasses import dataclass, field
from typing import Any

from .print import NOT_RETURNED

LEGAL_SUFFIXES = {"INC", "INCORPORATED", "LLC", "LTD", "CO", "CORP", "CORPORATION"}
"""Legal suffixes that carry no identifying information."""

ABBREVIATIONS = {
    "&": "AND",
    "ASSN": "ASSOCIATION",
    "ASSOC": "ASSOCIATION",
    "CTR": "CENTER",
    "CENTRE": "CENTER",
    "FDN": "FOUNDATION",
    "FND": "FOUNDATION",
    "INTL": "INTERNATIONAL",
    "NATL": "NATIONAL",
    "ORG": "ORGANIZATION",
    "SOC": "SOCIETY",
    "ST": "SAINT",
    "UNIV": "UNIVERSITY",
    "DEPT": "DEPARTMENT",
    "MT": "MOUNT",
}
"""Abbreviations seen in IRS records versus what applicants type."""

STREET_TYPES = {
    "POST OFFICE BOX": "PO BOX",
    "STREET": "ST",
    "AVENUE": "AVE",
    "ROAD": "RD",
    "BOULEVARD": "BLVD",
    "DRIVE": "DR",
    "LANE": "LN",
    "SUITE": "STE",
    "APARTMENT": "APT",
    "NORTH": "N",
    "SOUTH": "S",
    "EAST": "E",
    "WEST": "W",
}
"""Street-type abbreviations, for address lines."""

_NON_NAME = re.compile(r"[^A-Z0-9&]+")
_NON_ADDRESS = re.compile(r"[^A-Z0-9]+")


def _words(value: Any) -> list[str]:
    text = str(value).upper().replace("&", " & ")

    return [word for word in _NON_NAME.sub(" ", text).strip().split(" ") if word]


def normalize_name(value: Any) -> str | None:
    """Uppercase, punctuation-free, abbreviation-expanded, suffix-free."""
    if value is None or value is NOT_RETURNED:
        return None

    expanded = [ABBREVIATIONS.get(word, word) for word in _words(value)]

    while len(expanded) > 1 and expanded[-1] in LEGAL_SUFFIXES:
        expanded.pop()

    return " ".join(expanded)


def normalize_address_line(value: Any) -> str | None:
    """Uppercase, punctuation-free, street types abbreviated to the USPS short form."""
    if value is None or value is NOT_RETURNED:
        return None

    text = str(value).upper()

    for long, short in STREET_TYPES.items():
        text = re.sub(rf"\b{long}\b", short, text)

    return _NON_ADDRESS.sub(" ", text).strip()


def normalize_zip(value: Any) -> str | None:
    """ZIP+4 and ZIP5 compare on the five-digit prefix."""
    if value is None or value is NOT_RETURNED:
        return None

    digits = re.sub(r"\D", "", str(value))

    return digits[:5] if digits else None


@dataclass(frozen=True)
class Candidate:
    source: str
    value: Any
    normalized: str | None


@dataclass(frozen=True)
class NameComparison:
    outcome: str
    """``exact`` | ``normalized`` | ``mismatch`` | ``not_returned``."""

    matched_field: str | None
    submitted: str | None
    candidates: list[Candidate] = field(default_factory=list)


def compare_name(submitted: Any, candidates: Mapping[str, Any]) -> NameComparison:
    """
    Compares a submitted name against the names the API returned.

    Reports which field matched and the normalized forms, so a reviewer can see
    the reasoning rather than only the conclusion.
    """
    target = normalize_name(submitted)
    comparable = [
        (source, value)
        for source, value in candidates.items()
        if value is not None and value is not NOT_RETURNED
    ]

    if not comparable:
        return NameComparison("not_returned", None, target, [])

    normalized = [
        Candidate(source=source, value=value, normalized=normalize_name(value))
        for source, value in comparable
    ]

    for entry in normalized:
        if entry.value == submitted:
            return NameComparison("exact", entry.source, target, normalized)

    for entry in normalized:
        if entry.normalized == target:
            return NameComparison("normalized", entry.source, target, normalized)

    return NameComparison("mismatch", None, target, normalized)


@dataclass(frozen=True)
class FieldComparison:
    outcome: str
    """``exact`` | ``normalized`` | ``mismatch`` | ``not_returned`` | ``not_submitted``."""

    submitted: Any
    returned: Any


def compare_address_field(
    submitted: Any,
    returned: Any,
    normalize: Callable[[Any], str | None] = normalize_address_line,
) -> FieldComparison:
    """
    Compares one address component.

    ``not_returned`` is its own outcome. Treating an absent city as a matching
    city is the quiet failure this function exists to prevent.
    """
    if returned is None or returned is NOT_RETURNED:
        return FieldComparison("not_returned", submitted, returned)

    if submitted is None or submitted is NOT_RETURNED or str(submitted).strip() == "":
        return FieldComparison("not_submitted", submitted, returned)

    if submitted == returned:
        return FieldComparison("exact", submitted, returned)

    agrees = normalize(submitted) == normalize(returned)

    return FieldComparison("normalized" if agrees else "mismatch", submitted, returned)


def is_agreement(outcome: str) -> bool:
    """True for outcomes that agree, however loosely. Absence never counts."""
    return outcome in ("exact", "normalized")
