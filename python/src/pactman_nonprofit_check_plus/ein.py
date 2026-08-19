"""
EIN normalization and validation.

Formatting validation only. Passing these checks says nothing about whether an
organization is tax-exempt, in good standing, or eligible for anything — only
that the value is shaped like an EIN. No IRS prefix rules are applied.
"""

from __future__ import annotations

import re
from collections.abc import Sequence
from typing import Any

from .errors import PactmanValidationError, ValidationIssue

EIN_LENGTH = 9
"""Number of digits in an EIN."""

# Accepted input shapes: nine digits, optionally with the conventional hyphen
# after the two-digit prefix. Surrounding whitespace is ignored.
_EIN_PATTERN = re.compile(r"^\d{2}-?\d{7}$")


def normalize_ein(value: Any, index: int | None = None) -> str:
    """
    Normalizes an EIN to the nine-digit form the API expects.

    ``"41-1787097"`` and ``"411787097"`` both normalize to ``"411787097"``.

    :raises PactmanValidationError: if the value is not shaped like an EIN.
    """
    issue = _ein_issue(value, index)

    if issue is not None:
        raise PactmanValidationError(issue.message, [issue])

    return _clean(value)


def normalize_eins(values: Sequence[Any]) -> list[str]:
    """
    Normalizes a collection of EINs, reporting every failure at once.

    Duplicates are preserved and order is retained; see
    :meth:`.NonprofitsResource.check_bulk` for the optional ``dedupe`` behaviour.

    :raises PactmanValidationError: if any item is not shaped like an EIN. The
        error's ``issues`` identify the failing item by index and original value.
    """
    issues: list[ValidationIssue] = []
    normalized: list[str] = []

    for index, value in enumerate(values):
        issue = _ein_issue(value, index)

        if issue is not None:
            issues.append(issue)
            continue

        normalized.append(_clean(value))

    if issues:
        positions = ", ".join(str(issue.index) for issue in issues)
        raise PactmanValidationError(
            f"{len(issues)} of {len(values)} EINs are invalid (at index {positions}). "
            "No request was sent.",
            issues,
        )

    return normalized


def is_valid_ein(value: Any) -> bool:
    """True when ``value`` is shaped like an EIN. Never raises."""
    return _ein_issue(value) is None


def _clean(value: Any) -> str:
    """Strips a value that :func:`_ein_issue` has already confirmed is EIN-shaped."""
    return str(value).strip().replace("-", "")


def _ein_issue(value: Any, index: int | None = None) -> ValidationIssue | None:
    at = "" if index is None else f" at index {index}"

    if value is None:
        return ValidationIssue(f"EIN{at} is required.", index, value)

    if not isinstance(value, str):
        return ValidationIssue(
            f"EIN{at} must be a string, received {type(value).__name__}.", index, value
        )

    trimmed = value.strip()

    if trimmed == "":
        return ValidationIssue(f"EIN{at} is empty.", index, value)

    if not _EIN_PATTERN.match(trimmed):
        return ValidationIssue(
            f"EIN{at} must be {EIN_LENGTH} digits, optionally hyphenated as "
            f'XX-XXXXXXX. Received "{trimmed}".',
            index,
            value,
        )

    return None
