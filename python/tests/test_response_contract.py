"""
``response_contract.json`` restates, in the token vocabulary the live smoke test
speaks, what ``types.py`` declares. Two files saying the same thing can disagree,
and a contract that has drifted from the types it claims to mirror would check a
live deployment against a promise the package no longer makes.

These tests hold them together: same fields, and every token justified by the
declared type. Adding a field to ``Nonprofit`` fails here until the contract
learns about it, which is the point — a new field is a new prediction.
"""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any

import pytest

from pactman_nonprofit_check_plus.types import (
    ApiEnvelope,
    ApiErrorDetail,
    Nonprofit,
    OrganizationType,
)

CONTRACT_PATH = (
    Path(__file__).resolve().parents[1]
    / "src"
    / "pactman_nonprofit_check_plus"
    / "response_contract.json"
)

CONTRACT: dict[str, Any] = json.loads(CONTRACT_PATH.read_text(encoding="utf-8"))

# Each contract section and the TypedDict it restates.
#
# ``data`` is the envelope's open slot; each endpoint fills it with a record or a
# list of them, so the contract supplies it at composition rather than declaring
# it once here.
SHAPES: list[tuple[str, type, set[str]]] = [
    ("envelope", ApiEnvelope, {"data"}),
    ("errorDetail", ApiErrorDetail, set()),
    ("nonprofit", Nonprofit, set()),
    ("organizationType", OrganizationType, set()),
]

IDS = [shape for shape, _, _ in SHAPES]


def source_text(declared: object) -> str:
    """
    The annotation as it was written, whatever the interpreter kept it as.

    ``from __future__ import annotations`` in ``types.py`` means the declaration
    is never evaluated, which is what these tests want — the type as a human
    reads it, not a resolved runtime object. What that leaves behind differs by
    version: a plain string up to 3.13, and a ``ForwardRef`` wrapping the same
    string from 3.14, where annotations became lazy in their own right.
    """
    argument = getattr(declared, "__forward_arg__", None)

    return argument if isinstance(argument, str) else str(declared)


def declared_members(model: type, skip: set[str]) -> dict[str, str]:
    """Declared fields of a TypedDict, as field name to the source text of its type."""
    annotations = {
        field: source_text(declared)
        for field, declared in model.__annotations__.items()
        if field not in skip
    }

    assert annotations, f"{model.__name__} declares no fields"

    return annotations


def split_union(declared: str) -> list[str]:
    """Top-level members of a union, leaving anything inside brackets alone."""
    parts: list[str] = []
    depth = 0
    current = ""

    for character in declared:
        if character in "[(":
            depth += 1
        elif character in "])":
            depth -= 1

        if character == "|" and depth == 0:
            parts.append(current.strip())
            current = ""

            continue

        current += character

    parts.append(current.strip())

    return parts


def permitted_by(declared: str) -> set[str]:
    """The token kinds a declared Python type permits."""
    permitted: set[str] = set()

    for part in split_union(declared):
        if part == "None":
            permitted.add("null")
        elif part == "bool":
            permitted.add("boolean")
        elif part in ("int", "float"):
            permitted.add("number")
        elif part == "str":
            permitted.add("string")
        elif part.startswith(("list[", "Sequence[")):
            permitted.add("array")
        else:
            permitted.add("object")

    return permitted


STRING_TOKENS = frozenset(
    {"string", "text", "date", "date:iso", "url", "ofac-sentence", "empty"}
)


def justified(token: str, permitted: set[str]) -> bool:
    """Whether one contract token is justified by the declared type."""
    if token in STRING_TOKENS or token.startswith("digits:"):
        return "string" in permitted

    return token in permitted


@pytest.mark.parametrize(("section", "model", "skip"), SHAPES, ids=IDS)
def test_predicts_exactly_the_fields_the_model_declares(
    section: str, model: type, skip: set[str]
) -> None:
    declared = sorted(declared_members(model, skip))

    assert sorted(CONTRACT[section]) == declared


@pytest.mark.parametrize(("section", "model", "skip"), SHAPES, ids=IDS)
def test_every_token_is_justified_by_the_declared_type(
    section: str, model: type, skip: set[str]
) -> None:
    declared = declared_members(model, skip)

    for field, allowed in CONTRACT[section].items():
        assert field in declared, f"{field} is in the contract but not in {model.__name__}"

        permitted = permitted_by(declared[field])

        for token in allowed.split("|"):
            assert justified(token, permitted), (
                f"{model.__name__}.{field} is declared `{declared[field]}`, "
                f"which permits no {token} value"
            )


@pytest.mark.parametrize(("section", "model", "skip"), SHAPES, ids=IDS)
def test_marks_a_field_nullable_exactly_when_the_declared_type_does(
    section: str, model: type, skip: set[str]
) -> None:
    declared = declared_members(model, skip)

    for field, allowed in CONTRACT[section].items():
        assert ("null" in allowed.split("|")) == ("null" in permitted_by(declared[field])), (
            f"{model.__name__}.{field} is declared `{declared[field]}` "
            f"but the contract says `{allowed}`"
        )
