"""
Environment selection and base-URL resolution.

Endpoint hosts are declared here and nowhere else. Nothing in this package
should contain a literal Pactman host.
"""

from __future__ import annotations

from enum import Enum


class PactmanEnvironment(str, Enum):
    """Named Pactman environments that are supported for public SDK use."""

    PRODUCTION = "production"
    """The Pactman production API."""

    def __str__(self) -> str:
        return self.value


# Pactman's QA, SIT and sandbox hosts are internal and are deliberately not
# exposed here. Point at one with the ``base_url`` option if you have been given
# access to it.
_BASE_URLS: dict[PactmanEnvironment, str] = {
    PactmanEnvironment.PRODUCTION: "https://entities.pactman.org",
}

DEFAULT_ENVIRONMENT = PactmanEnvironment.PRODUCTION
"""The environment used when none is supplied."""

SINGLE_CHECK_PATH = "/api/entities/nonprofitcheck/v1/us/ein/{ein}"
"""Path of the single-check endpoint. ``{ein}`` is replaced with a normalized EIN."""

BULK_CHECK_PATH = "/api/entities/nonprofitcheckbulk/v1/us/eins"
"""Path of the bulk-check endpoint."""

MAX_BULK_EINS = 50
"""
Maximum number of EINs the API accepts in one bulk request.

This mirrors the server-side limit. It is declared once, here.
"""


def base_url_for_environment(environment: PactmanEnvironment | str) -> str:
    """Returns the base URL for a named environment."""
    try:
        resolved = PactmanEnvironment(environment)
    except ValueError:
        supported = ", ".join(member.value for member in PactmanEnvironment)
        raise ValueError(
            f'Unknown Pactman environment "{environment}". Supported: {supported}.'
        ) from None

    return _BASE_URLS[resolved]


def supported_environments() -> list[PactmanEnvironment]:
    """Every environment name the SDK understands."""
    return list(PactmanEnvironment)
