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
    "baseline_diff",
    "compose_expected",
    "contract_diff",
    "coverage_diff",
    "format_changes",
    "format_of",
    "permits",
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

    unreachable: int = 0
    """
    Paths the expectation predicts that had nowhere to arrive, counted rather
    than reported. :func:`coverage_diff` and :func:`baseline_diff` set this.
    """

    nullable: int = 0
    """
    Paths that differ only over whether a value arrived, counted rather than
    reported. Only :func:`baseline_diff` sets this.
    """

    optional_absent: int = 0
    """
    Paths the types declare optional that the response did not carry, counted
    rather than reported. Only :func:`coverage_diff` sets this.
    """


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


def baseline_diff(before: dict[str, str], current: dict[str, str]) -> Diff:
    """
    The recording held against a live response, with the differences a recording
    cannot speak to left out.

    A baseline is one organization's response on one afternoon, so much of what
    separates it from today's run is not the API moving — it is a different
    subject, or the same subject whose Pub 78 row lapsed since. Two kinds of
    difference fall out of that, and neither is drift.

    Nullability. ``pub78_city`` was ``text`` when the recording was made and is
    ``null`` now. The field is still there and still declared ``str | None``;
    this organization simply has no Pub 78 city. Only a move between two forms a
    value actually took — ``digits:9`` to ``text`` — says the API changed.

    Reachability. ``organization_types`` arrived null, so the paths beneath it
    had nowhere to be and read as removed. :func:`coverage_diff` already excuses
    that against the contract; a recording needs it in both directions, because
    which side has the populated parent is an accident of which ran first.

    Both are counted rather than dropped, so a green run still says how much it
    passed over. What the recording cannot answer, the contract checks do: a
    field that must not be null is declared that way in
    ``response_contract.json``, and :func:`contract_diff` fails on it there.
    """
    changes: list[Change] = []
    nullable = 0
    unreachable = 0

    for path, token in before.items():
        if path in current:
            if current[path] == token:
                continue

            if _nullability_only(token, current[path]):
                nullable += 1
                continue

            changes.append(
                Change(kind="changed", path=path, from_token=token, to_token=current[path])
            )
            continue

        if _unreachable_in(path, current):
            unreachable += 1
            continue

        changes.append(Change(kind="removed", path=path, token=token))

    for path, token in current.items():
        if path in before:
            continue

        if _unreachable_in(path, before):
            unreachable += 1
            continue

        changes.append(Change(kind="added", path=path, token=token))

    return Diff(
        changes=_sorted(changes),
        total=len(changes),
        nullable=nullable,
        unreachable=unreachable,
    )


def _nullability_only(before: str, after: str) -> bool:
    """
    Whether two tokens differ only over whether a value arrived.

    Drop ``null`` from both sides and compare what is left. ``date`` against
    ``date|null`` leaves the same form on each. ``date`` against ``null`` leaves
    one side with nothing, and a side that recorded no form makes no claim about
    the form — so there is nothing there to have moved. ``digits:9`` against
    ``text`` leaves two different forms, which is drift and stays reported.
    """
    left = _without_null(before)
    right = _without_null(after)

    return not left or not right or left == right


def _without_null(token: str) -> list[str]:
    """A token's forms, in the order signatures store them, with ``null`` dropped."""
    return [one for one in token.split("|") if one != "null"]


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


def format_changes(changes: list[Change], *, indent: str = "      ") -> str:
    """
    One line per change, indented to sit under a check's own line.

    Every change, with nothing elided. A run that says a field moved and then
    hides which one sends you back to the deployment to find out by hand, and the
    list is only long when something large moved — which is exactly when the
    whole of it is what you need.
    """
    lines = [
        f"~ {change.path}: {change.from_token} → {change.to_token}"
        if change.kind == "changed"
        else f"{_MARKS[change.kind]} {change.path} ({change.token})"
        for change in changes
    ]

    return "\n".join(f"{indent}{line}" for line in lines)


# --- the package's own prediction ---------------------------------------------
#
# Everything above compares one live response against another recorded earlier,
# which answers "did the API move?" but never "does the API still match what this
# package tells its users?". The second question is the one with a caller on the
# other end of it: ``types.py`` promises ``bmf_status`` is a bool, and a user
# writes ``if record.get("bmf_status")`` on the strength of that promise. Nothing
# in a self-recorded baseline can notice when the API disagrees, because the
# baseline is the API's own output — it agrees with itself by construction.
#
# ``response_contract.json`` is the other side of that comparison: the shape this
# package predicts, in the same token vocabulary as a signature so the two can be
# held against each other directly. It is checked in, identical for everyone, and
# derived from the declared types rather than from anyone's account — so a diff to
# it is a deliberate change to what the SDK promises, reviewable as such, rather
# than a record of what one organization looked like on one afternoon.

# String tokens ``string`` stands for, when the package claims no format.
_STRING_TOKENS = frozenset({"text", "date", "date:iso", "url", "ofac-sentence", "empty"})


def _is_string_token(token: str) -> bool:
    return token in _STRING_TOKENS or token.startswith("digits:")


def permits(allowed: str, token: str) -> bool:
    """
    Whether an observed token is one the contract allows.

    ``string`` is a wildcard over every string token, because a declared ``string``
    makes no claim about the form of the value. Where the package does make one —
    an EIN is nine digits, a timestamp is ``M/D/YYYY h:mm:ss AM`` — the contract
    names that token instead, and a value that stops matching it fails even though
    it is still, technically, a string. That is the point: a timestamp that turns
    ISO breaks every caller parsing it, and the declared type never notices.
    """
    tokens = allowed.split("|")

    return token in tokens or ("string" in tokens and _is_string_token(token))


def compose_expected(contract: dict[str, Any], kind: str) -> dict[str, str]:
    """
    The flat expected signature for one endpoint, built from the shared parts.

    The record is described once and used for both endpoints, so single and bulk
    cannot drift apart in the contract the way they can on the wire — where
    ``bmf_status`` arrives as a string from one and a bool from the other. One
    description means one of those two has to be reported as wrong.
    """
    single = kind == "single"
    prefix = "data." if single else "data[]."

    expected: dict[str, str] = {
        **contract["envelope"],
        "data": "null|object" if single else "array|null",
        "errors[]": "object",
        "errors[].eins[]": "string",
    }

    for field, token in contract["errorDetail"].items():
        expected[f"errors[].{field}"] = token

    if not single:
        expected["data[]"] = "object"

    for field, token in contract["nonprofit"].items():
        expected[f"{prefix}{field}"] = token

    # Nullable elements, not just a nullable array: the API sends a null in the
    # list where Publication 78 has a deductibility row it cannot resolve, so a
    # caller reading ``types[0]["organization_type"]`` has to check. ``types.py``
    # declares the same thing.
    expected[f"{prefix}organization_types[]"] = "null|object"

    for field, token in contract["organizationType"].items():
        expected[f"{prefix}organization_types[].{field}"] = token

    return {path: expected[path] for path in sorted(expected)}


def contract_diff(
    expected: dict[str, str],
    observed: dict[str, str],
    required: set[str] | None = None,
) -> Diff:
    """
    Paths the live response carries a value the contract permits no form of.

    Paths the contract has never heard of are :func:`coverage_diff`'s to report,
    so a field the API invented is one failure rather than two.

    ``required`` is accepted and ignored, so that every differ the live run picks
    between has one signature. Whether a field was obliged to arrive has no
    bearing on whether the value that did arrive is one the contract permits.
    """
    changes = []

    for path, token in observed.items():
        allowed = expected.get(path)

        if allowed is None:
            continue

        offending = [one for one in token.split("|") if not permits(allowed, one)]

        if offending:
            changes.append(
                Change(
                    kind="changed",
                    path=path,
                    from_token=allowed,
                    to_token="|".join(offending),
                )
            )

    return Diff(changes=_sorted(changes), total=len(changes))


def coverage_diff(
    expected: dict[str, str],
    observed: dict[str, str],
    required: set[str] | None = None,
) -> Diff:
    """
    Fields the API sent that the package does not predict, and fields it predicts
    that the API did not send.

    Both directions fail. An unpredicted field is readable only by a caller who
    already knows to look — ``Nonprofit`` being a ``total=False`` TypedDict over a
    plain dict hides it from everyone else — and a predicted field that stopped
    arriving breaks every caller that reads it. The declared types notice neither,
    so this is the only place either one is caught.

    The exception is a path that had nowhere to arrive: ``errors[].reason`` while
    ``errors`` is null, ``data.organization_types[].organization_type`` while that
    array is null or empty. The parent already accounts for the child's absence,
    and every successful response has a null ``errors`` — reporting those would
    fail every green run and say nothing. They are counted as unreachable.

    A container that vanished is reported once, at its shallowest path: a ``data``
    that stopped arriving is one failure, not fifty-nine.
    """
    changes = [
        Change(kind="added", path=path, token=token)
        for path, token in observed.items()
        if path not in expected
    ]

    absent = [path for path in expected if path not in observed]
    missing = set(absent)
    unreachable = 0
    optional_absent = 0

    for path in absent:
        if _unreachable_in(path, observed):
            unreachable += 1
            continue

        if any(ancestor in missing for ancestor in _ancestors_of(path)):
            continue

        # A field the types declare optional is permitted to be absent — that is
        # what ``total=False`` means. Reporting it would fail a response the
        # package's own declared types accept. ``required`` carries the policy;
        # without one every predicted path is treated as required, which is what
        # the differ did before a caller could say otherwise.
        if required is not None and path not in required:
            optional_absent += 1
            continue

        changes.append(Change(kind="removed", path=path, token=expected[path]))

    return Diff(
        changes=_sorted(changes),
        total=len(changes),
        unreachable=unreachable,
        optional_absent=optional_absent,
    )


def required_paths_of(contract: dict[str, Any], kind: str) -> set[str]:
    """
    The paths a response must carry: the structural ones every envelope has, and
    whatever the declared types mark as required.

    Optionality is the promise the package actually makes. ``Nonprofit`` is a
    ``total=False`` TypedDict, so every field on it may be absent, and failing on
    an absence tests the deployment's current data rather than the contract.
    """
    single = kind == "single"
    prefix = "data." if single else "data[]."
    required = contract.get("required") or {}

    paths = {"data", "errors[]", "errors[].eins[]", f"{prefix}organization_types[]"}

    if not single:
        paths.add("data[]")

    for field in required.get("envelope") or []:
        paths.add(field)

    for field in required.get("errorDetail") or []:
        paths.add(f"errors[].{field}")

    for field in required.get("nonprofit") or []:
        paths.add(f"{prefix}{field}")

    for field in required.get("organizationType") or []:
        paths.add(f"{prefix}organization_types[].{field}")

    return paths


def _ancestors_of(path: str) -> list[str]:
    """
    Every enclosing path of a signature path, innermost first.

        data.organization_types[].organization_type
          → data.organization_types[], data.organization_types, data
    """
    ancestors: list[str] = []
    rest = path

    while True:
        if rest.endswith("[]"):
            rest = rest[:-2]
        else:
            head, separator, _ = rest.rpartition(".")

            if separator == "":
                return ancestors

            rest = head

        ancestors.append(rest)


def _unreachable_in(path: str, observed: dict[str, str]) -> bool:
    """
    Whether a container above this path arrived in a form with no room for it.

    A null has no members and an empty array has no elements, so nothing under
    either was ever going to appear.
    """
    for ancestor in _ancestors_of(path):
        token = observed.get(ancestor)

        if token is None:
            continue

        tokens = token.split("|")

        if all(one == "null" for one in tokens):
            return True

        if "array" in tokens and f"{ancestor}[]" not in observed:
            return True

    return False
