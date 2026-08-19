"""
Error taxonomy.

Every error raised by this SDK is a :class:`PactmanError` carrying a stable
:class:`PactmanErrorCategory` and a :class:`PactmanErrorOrigin`, so callers can
branch on exception type or category without parsing message strings.

API keys are never placed into an error message, an error attribute, or any
``to_dict`` output.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from enum import Enum
from typing import Any

from .types import ApiEnvelope, ApiErrorDetail


class PactmanErrorCategory(str, Enum):
    """Stable, machine-comparable error categories."""

    CONFIGURATION = "configuration"
    """The client was constructed with unusable options."""

    VALIDATION = "validation"
    """Input failed the SDK's local validation; no request was sent."""

    AUTHENTICATION = "authentication"
    """HTTP 401. The API key is missing, malformed, revoked or unrecognized."""

    AUTHORIZATION = "authorization"
    """HTTP 403. The key is valid but lacks access to the resource."""

    BAD_REQUEST = "bad_request"
    """HTTP 400. The API rejected the request."""

    NOT_FOUND = "not_found"
    """HTTP 404. No matching record."""

    RATE_LIMIT = "rate_limit"
    """HTTP 429. Rate limit exceeded."""

    SERVER = "server"
    """HTTP 5xx."""

    TIMEOUT = "timeout"
    """The request exceeded the configured timeout."""

    NETWORK = "network"
    """The request never produced an HTTP response."""

    API = "api"
    """An API error that does not fall into a more specific category."""

    def __str__(self) -> str:
        return self.value


class PactmanErrorOrigin(str, Enum):
    """Whether an error was raised locally or derived from an API response."""

    LOCAL = "local"
    API = "api"

    def __str__(self) -> str:
        return self.value


class PactmanError(Exception):
    """Base class for every error this SDK raises."""

    category: PactmanErrorCategory
    origin: PactmanErrorOrigin

    def __init__(
        self,
        message: str,
        category: PactmanErrorCategory,
        origin: PactmanErrorOrigin,
    ) -> None:
        super().__init__(message)
        self.message = message
        self.category = category
        self.origin = origin

    def to_dict(self) -> dict[str, Any]:
        """A serializable view of the error. Never contains the API key."""
        return {
            "name": type(self).__name__,
            "message": self.message,
            "category": self.category.value,
            "origin": self.origin.value,
        }


class PactmanConfigurationError(PactmanError):
    """The client options were unusable — a missing API key, a malformed base URL."""

    def __init__(self, message: str) -> None:
        super().__init__(
            message, PactmanErrorCategory.CONFIGURATION, PactmanErrorOrigin.LOCAL
        )


@dataclass(frozen=True)
class ValidationIssue:
    """One item that failed local validation."""

    message: str
    """Human-readable reason the value was rejected."""

    index: int | None = None
    """Position in the input collection, for bulk calls."""

    value: Any = None
    """The offending value, as supplied by the caller."""

    def to_dict(self) -> dict[str, Any]:
        return {"message": self.message, "index": self.index, "value": self.value}


class PactmanValidationError(PactmanError):
    """
    Input failed local validation. No HTTP request was sent.

    Distinguishable from an API-side 400 by ``origin is PactmanErrorOrigin.LOCAL``.
    """

    def __init__(self, message: str, issues: list[ValidationIssue] | None = None) -> None:
        super().__init__(
            message, PactmanErrorCategory.VALIDATION, PactmanErrorOrigin.LOCAL
        )
        self.issues = list(issues) if issues else []

    def to_dict(self) -> dict[str, Any]:
        return {**super().to_dict(), "issues": [issue.to_dict() for issue in self.issues]}


@dataclass(frozen=True)
class PactmanApiErrorInit:
    """Fields shared by every error derived from an HTTP response."""

    status: int
    """HTTP status code."""

    api_message: str | None = None
    """``message`` from the Pactman response envelope, when present."""

    api_code: int | None = None
    """``code`` from the Pactman response envelope, when present."""

    api_errors: list[ApiErrorDetail] = field(default_factory=list)
    """``errors`` from the Pactman response envelope, normalized to a list."""

    request_id: str | None = None
    """Correlation identifier from the response headers, when present."""

    retry_after_seconds: float | None = None
    """``Retry-After`` in seconds, when the server supplied a valid value."""

    raw: ApiEnvelope | str | None = None
    """The parsed response body, or the raw text when it was not JSON."""

    attempts: int = 1
    """How many attempts were made before this error was surfaced."""


class PactmanApiError(PactmanError):
    """
    An error returned by the Pactman API.

    Raised directly when the status maps to no more specific subclass; response
    metadata is preserved even when the body could not be deserialized.
    """

    def __init__(
        self,
        message: str,
        init: PactmanApiErrorInit,
        category: PactmanErrorCategory = PactmanErrorCategory.API,
    ) -> None:
        super().__init__(message, category, PactmanErrorOrigin.API)
        self.status = init.status
        self.api_message = init.api_message
        self.api_code = init.api_code
        self.api_errors = list(init.api_errors)
        self.request_id = init.request_id
        self.retry_after_seconds = init.retry_after_seconds
        self.raw = init.raw
        self.attempts = init.attempts

    def to_dict(self) -> dict[str, Any]:
        return {
            **super().to_dict(),
            "status": self.status,
            "api_message": self.api_message,
            "api_code": self.api_code,
            "api_errors": self.api_errors,
            "request_id": self.request_id,
            "retry_after_seconds": self.retry_after_seconds,
            "attempts": self.attempts,
        }


class PactmanAuthenticationError(PactmanApiError):
    """HTTP 401."""

    def __init__(self, message: str, init: PactmanApiErrorInit) -> None:
        super().__init__(message, init, PactmanErrorCategory.AUTHENTICATION)


class PactmanAuthorizationError(PactmanApiError):
    """HTTP 403."""

    def __init__(self, message: str, init: PactmanApiErrorInit) -> None:
        super().__init__(message, init, PactmanErrorCategory.AUTHORIZATION)


class PactmanBadRequestError(PactmanApiError):
    """HTTP 400. The API rejected the request; see ``api_errors`` for the reasons."""

    def __init__(self, message: str, init: PactmanApiErrorInit) -> None:
        super().__init__(message, init, PactmanErrorCategory.BAD_REQUEST)


class PactmanNotFoundError(PactmanApiError):
    """HTTP 404."""

    def __init__(self, message: str, init: PactmanApiErrorInit) -> None:
        super().__init__(message, init, PactmanErrorCategory.NOT_FOUND)


class PactmanRateLimitError(PactmanApiError):
    """HTTP 429. ``retry_after_seconds`` carries the server's ``Retry-After`` when sent."""

    def __init__(self, message: str, init: PactmanApiErrorInit) -> None:
        super().__init__(message, init, PactmanErrorCategory.RATE_LIMIT)


class PactmanServerError(PactmanApiError):
    """HTTP 5xx."""

    def __init__(self, message: str, init: PactmanApiErrorInit) -> None:
        super().__init__(message, init, PactmanErrorCategory.SERVER)


class PactmanTimeoutError(PactmanError):
    """The request exceeded the configured timeout."""

    def __init__(self, message: str, timeout: float, attempts: int = 1) -> None:
        super().__init__(message, PactmanErrorCategory.TIMEOUT, PactmanErrorOrigin.LOCAL)
        self.timeout = timeout
        """The timeout that elapsed, in seconds."""
        self.attempts = attempts

    def to_dict(self) -> dict[str, Any]:
        return {**super().to_dict(), "timeout": self.timeout, "attempts": self.attempts}


class PactmanNetworkError(PactmanError):
    """The request produced no HTTP response."""

    def __init__(self, message: str, attempts: int = 1) -> None:
        super().__init__(message, PactmanErrorCategory.NETWORK, PactmanErrorOrigin.LOCAL)
        self.attempts = attempts

    def to_dict(self) -> dict[str, Any]:
        return {**super().to_dict(), "attempts": self.attempts}


def is_pactman_error(value: object) -> bool:
    """True when ``value`` is any error raised by this SDK."""
    return isinstance(value, PactmanError)


def error_from_status(init: PactmanApiErrorInit) -> PactmanApiError:
    """Builds the error subclass that matches an HTTP status code."""
    status = init.status
    message = (init.api_message or "").strip() or _default_message_for_status(status)

    if status == 400:
        return PactmanBadRequestError(message, init)
    if status == 401:
        return PactmanAuthenticationError(message, init)
    if status == 403:
        return PactmanAuthorizationError(message, init)
    if status == 404:
        return PactmanNotFoundError(message, init)
    if status == 429:
        return PactmanRateLimitError(message, init)
    if status >= 500:
        return PactmanServerError(message, init)

    return PactmanApiError(message, init)


def _default_message_for_status(status: int) -> str:
    if status == 400:
        return "The Pactman API rejected the request."
    if status == 401:
        return "The Pactman API key was rejected."
    if status == 403:
        return "This Pactman API key is not permitted to access that resource."
    if status == 404:
        return "No matching record was found."
    if status == 429:
        return "The Pactman API rate limit was exceeded."
    if status >= 500:
        return f"The Pactman API returned a server error (HTTP {status})."

    return f"The Pactman API returned an unexpected response (HTTP {status})."
