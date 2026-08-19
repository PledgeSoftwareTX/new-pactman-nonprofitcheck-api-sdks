"""
Signatures of a JSON response, and the differences between two of them.

A recorded copy of a live response is worthless as a drift detector: every run
returns a fresh ``report_date``, a different ``timeTaken`` and a usage counter
that only goes up, so a byte comparison fails for reasons that have nothing to
do with the API changing. What is stable is the shape — which fields exist, what
type each carries, and what form its values take. That is what a signature
captures, and comparing one against a recorded baseline is how ``smoke_live.py``
answers "has the API changed?" without re-recording every time the IRS data
behind an organization is refreshed.

A signature is a flat, sorted map of path to type token::

    {
      "code": "number",
      "data.ein": "digits:9",
      "data.most_recent_bmf": "date",
      "data.organization_types[].deductibility_limitation": "text",
      "data.pub78_verified": "boolean",
      "data.revocation_code": "null",
      "errors": "null"
    }

Flat, so a field that appears, disappears or changes type is one line in a git
diff, and so comparing two signatures is a key-by-key walk rather than a
recursive descent that has to re-derive structure it already knows.

The two halves are compared separately — :func:`schema_diff` over the paths,
:func:`type_diff` over the tokens — because they fail for different reasons and
mean different things. A field that disappeared breaks callers that read it; a
field that changed type breaks callers that parse it. Reporting them as one
number would say only that something moved.

Tokens
    object, array, boolean, number, null   the JSON type, structural
    date            ``M/D/YYYY h:mm:ss AM`` — the format every API timestamp uses
    date:iso        an ISO-8601 timestamp, which this API does not currently send
    digits:9        a string of digits, grouped by length: "411787097" is
                    digits:9, "01085-2643" is digits:5-4, "00" is digits:2
    url             an http(s) URL
    ofac-sentence   the SDN sentence ``ofac_status`` carries, in either wording
    empty           an empty or whitespace-only string
    text            any other string

A path that carries more than one token across a single response — a field that
is a date on one organization in a bulk batch and null on another — records them
sorted and joined by ``"|"``, as in ``date|null``.

Only shapes go in. No value from the response is ever recorded, so a baseline is
safe to commit and a diff is safe to print.
"""

from __future__ import annotations

import re
from dataclasses import dataclass
from typing import Any

__all__ = [
    "Change",
    "Diff",
    "format_changes",
    "format_of",
    "schema_diff",
    "signature_of",
    "summarize_changes",
    "type_diff",
]

# The format every timestamp in this API uses. See ``fixtures.api_date``.
API_DATE = re.compile(
    r"^\d{1,2}/\d{1,2}/\d{4},? \d{1,2}:\d{2}:\d{2} ?(?:AM|PM)$", re.IGNORECASE
)

ISO_DATE = re.compile(r"^\d{4}-\d{2}-\d{2}(?:[T ]\d{2}:\d{2}|$)")

# Digits, optionally in hyphen-separated groups: EINs, ZIPs, IRS codes.
DIGIT_GROUPS = re.compile(r"^\d+(?:-\d+)*$")

URL_LIKE = re.compile(r"^https?://", re.IGNORECASE)

# The clause both OFAC wordings share.
#
# Matching the clause rather than either whole sentence keeps a genuine change of
# wording visible — it would fall back to `text` — while a subject that goes from
# "was NOT included" to "may be included", or a possible match whose UID differs,
# stays the same shape. That is a change in the data, not the contract.
OFAC_SENTENCE = re.compile(r"Specially Designated Nationals ?\(SDN\) list", re.IGNORECASE)

# Runtimes that format times with a narrow no-break space; the API sends a plain
# one. Normalized so the same timestamp is not two different tokens.
_SPACES = re.compile("[\u00a0\u202f]")


@dataclass(frozen=True)
class Change:
    """One difference between a recorded signature and the live one."""

    kind: str
    """``removed``, ``changed`` or ``added``."""

    path: str
    token: str | None = None
    """The type token, for a path that was added or removed."""

    from_token: str | None = None
    to_token: str | None = None
    """What the token was and became, for a path that changed."""


@dataclass(frozen=True)
class Diff:
    """The changes along one axis, and how many there were."""

    changes: list[Change]
    total: int


def format_of(value: str) -> str:
    """Classifies a string by the form of its value, never by the value itself."""
    text = _SPACES.sub(" ", value)

    if text.strip() == "":
        return "empty"

    if API_DATE.match(text):
        return "date"

    if ISO_DATE.match(text):
        return "date:iso"

    if DIGIT_GROUPS.match(text):
        return "digits:" + "-".join(str(len(group)) for group in text.split("-"))

    if URL_LIKE.match(text):
        return "url"

    if OFAC_SENTENCE.search(text):
        return "ofac-sentence"

    return "text"


def _token_for(value: Any) -> str:
    if value is None:
        return "null"

    if isinstance(value, bool):
        return "boolean"

    if isinstance(value, (int, float)):
        return "number"

    if isinstance(value, str):
        return format_of(value)

    if isinstance(value, list):
        return "array"

    if isinstance(value, dict):
        return "object"

    return type(value).__name__


def _collect(value: Any, path: str, tokens: dict[str, set[str]]) -> None:
    if path != "":
        tokens.setdefault(path, set()).add(_token_for(value))

    # Every element of an array contributes to one path, so a batch of ten
    # organizations describes one record shape rather than ten.
    if isinstance(value, list):
        for item in value:
            _collect(item, f"{path}[]", tokens)

        return

    if isinstance(value, dict):
        for key, child in value.items():
            _collect(child, key if path == "" else f"{path}.{key}", tokens)


def signature_of(value: Any) -> dict[str, str]:
    """Builds the signature of a parsed JSON response."""
    tokens: dict[str, set[str]] = {}

    _collect(value, "", tokens)

    return {path: "|".join(sorted(tokens[path])) for path in sorted(tokens)}


def schema_diff(baseline: dict[str, str], current: dict[str, str]) -> Diff:
    """
    Fields the API stopped sending, and fields it started sending.

    Additions count. A field the API added is forward-compatible for a caller —
    the record is a plain dict either way — but it is still the API changing, and
    a baseline that quietly absorbs additions cannot tell you when it did.
    """
    changes = [
        Change(kind="removed", path=path, token=token)
        for path, token in baseline.items()
        if path not in current
    ]

    changes += [
        Change(kind="added", path=path, token=token)
        for path, token in current.items()
        if path not in baseline
    ]

    return Diff(changes=_sorted(changes), total=len(changes))


def type_diff(baseline: dict[str, str], current: dict[str, str]) -> Diff:
    """
    Fields whose type or value format changed, across the paths both signatures
    have. Paths only one of them has are :func:`schema_diff`'s to report, so a
    single renamed field is one failure rather than two.
    """
    changes = [
        Change(kind="changed", path=path, from_token=token, to_token=current[path])
        for path, token in baseline.items()
        if path in current and current[path] != token
    ]

    return Diff(changes=_sorted(changes), total=len(changes))


# Removals first: a field that disappeared breaks callers that read it.
_CHANGE_ORDER = {"removed": 0, "changed": 1, "added": 2}


def _sorted(changes: list[Change]) -> list[Change]:
    return sorted(changes, key=lambda change: (_CHANGE_ORDER[change.kind], change.path))


def summarize_changes(changes: list[Change]) -> str:
    """"2 removed, 1 added" — the counts that are not zero."""
    counts = {kind: 0 for kind in _CHANGE_ORDER}

    for change in changes:
        counts[change.kind] += 1

    parts = [f"{count} {kind}" for kind, count in counts.items() if count > 0]

    return ", ".join(parts) if parts else "no differences"


_MARKS = {"removed": "-", "changed": "~", "added": "+"}


def format_changes(changes: list[Change], *, indent: str = "      ", limit: int = 12) -> str:
    """One line per change, indented to sit under a check's own line."""
    lines = [
        f"~ {change.path}: {change.from_token} → {change.to_token}"
        if change.kind == "changed"
        else f"{_MARKS[change.kind]} {change.path} ({change.token})"
        for change in changes
    ]

    shown = lines[:limit]

    if len(lines) > len(shown):
        shown.append(f"… and {len(lines) - len(shown)} more")

    return "\n".join(f"{indent}{line}" for line in shown)
