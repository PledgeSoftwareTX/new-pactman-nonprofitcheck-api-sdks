"""
Console formatting for the examples.

The important rule here is :func:`render`: a field the API returned as ``None``
and a field the API did not return at all print differently. Collapsing them
into ``""`` or ``"-"`` is how a missing value quietly becomes a match.

JavaScript gets that distinction free from ``null`` versus ``undefined``. Python
needs a sentinel, so absence is :data:`NOT_RETURNED` and an explicit null stays
``None``.
"""

from __future__ import annotations

from collections.abc import Mapping
from typing import Any


class _NotReturned:
    """Absence of a field, as distinct from a field returned as ``None``."""

    _instance: _NotReturned | None = None

    def __new__(cls) -> _NotReturned:
        if cls._instance is None:
            cls._instance = super().__new__(cls)

        return cls._instance

    def __repr__(self) -> str:
        return "<not returned>"

    def __bool__(self) -> bool:
        return False


NOT_RETURNED = _NotReturned()
"""The API did not return this field at all."""


def pick(source: Mapping[str, Any] | None, key: str) -> Any:
    """
    Reads ``key``, distinguishing "absent" from "returned as null".

    The equivalent of JavaScript's ``source?.key``: a missing source and a
    missing key both yield :data:`NOT_RETURNED`, never ``None``.
    """
    if source is None or key not in source:
        return NOT_RETURNED

    return source[key]


def heading(text: str) -> None:
    print(f"\n{text}")
    print("─" * len(text))


def render(value: Any) -> str:
    """``<null>`` for an explicit null, ``<not returned>`` for an absent key."""
    if value is NOT_RETURNED:
        return "<not returned>"

    if value is None:
        return "<null>"

    if isinstance(value, (list, tuple)):
        return "<empty list>" if len(value) == 0 else f"{len(value)} entries"

    return str(value)


def field(label: str, value: Any, width: int = 32) -> None:
    print(f"  {str(label).ljust(width)} {render(value)}")


def bullet(text: str) -> None:
    print(f"  • {text}")


def note(text: str) -> None:
    """A short, single-line note. Used for policy statements and caveats."""
    print(f"\n{text}")
