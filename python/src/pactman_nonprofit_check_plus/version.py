"""
The SDK version, reported in the User-Agent header.

Kept in sync with ``pyproject.toml`` by a unit test rather than a build step, so
the value is importable without reading package metadata at runtime.
"""

VERSION = "1.0.0"
"""The distribution version, reported in the User-Agent header."""

PACKAGE_NAME = "pactman-nonprofit-check-plus"
"""The PyPI distribution name, reported in the User-Agent header."""
