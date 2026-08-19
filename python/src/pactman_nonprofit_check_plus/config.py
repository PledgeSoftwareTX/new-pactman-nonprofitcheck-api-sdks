"""
Client configuration: defaults, validation, and credential redaction.
"""

from __future__ import annotations

import math
import platform
import sys
from collections.abc import Mapping
from dataclasses import dataclass, field, replace
from typing import Any
from urllib.parse import urlsplit

from .environments import (
    DEFAULT_ENVIRONMENT,
    PactmanEnvironment,
    base_url_for_environment,
    supported_environments,
)
from .errors import PactmanConfigurationError
from .version import PACKAGE_NAME, VERSION

DEFAULT_TIMEOUT = 30.0
"""Default timeout per attempt, in seconds."""

_NEVER_RETRY_STATUSES = frozenset({400, 401, 403, 404})
"""Statuses that are never retried, regardless of ``retryable_statuses``."""


def _is_finite(value: Any) -> bool:
    """True for a real, finite number. ``True``/``False`` are ints and do not qualify."""
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return False

    return math.isfinite(value)


@dataclass(frozen=True)
class RetryOptions:
    """
    Retry policy. Applied per request, on top of the overall timeout.

    Every field has the SDK default, so ``RetryOptions(max_retries=5)`` is a
    complete policy rather than a patch. To adjust a client's policy for one
    request without restating it, pass a plain dict to the method's ``retry``
    argument — those keys are merged onto the client's policy.
    """

    max_retries: int = 2
    """Retries after the first attempt. ``0`` disables retrying."""

    initial_delay: float = 0.5
    """
    Delay before the first retry, in seconds. Subsequent delays grow by
    ``backoff_factor`` and are randomized when ``jitter`` is on.
    """

    max_delay: float = 8.0
    """
    Ceiling for a single backoff delay, in seconds. A server-supplied
    ``Retry-After`` is honored even when it exceeds this.
    """

    backoff_factor: float = 2.0

    jitter: bool = True
    """
    Randomize each delay across ``[0, computed]`` (full jitter) so that clients
    failing together do not retry in lockstep.
    """

    retryable_statuses: tuple[int, ...] = (429, 500, 502, 503, 504)
    """
    HTTP statuses worth retrying. Authentication, authorization, validation and
    not-found responses are never retried, whatever this contains.
    """

    respect_retry_after: bool = True
    """Wait for the server's ``Retry-After`` before falling back to backoff."""

    def __post_init__(self) -> None:
        if not isinstance(self.max_retries, int) or isinstance(self.max_retries, bool):
            raise PactmanConfigurationError("`max_retries` must be an integer of 0 or more.")

        if self.max_retries < 0:
            raise PactmanConfigurationError("`max_retries` must be an integer of 0 or more.")

        if not _is_finite(self.initial_delay) or self.initial_delay < 0:
            raise PactmanConfigurationError("`initial_delay` must be 0 or more.")

        if not _is_finite(self.max_delay) or self.max_delay < 0:
            raise PactmanConfigurationError("`max_delay` must be 0 or more.")

        if not _is_finite(self.backoff_factor) or self.backoff_factor < 1:
            raise PactmanConfigurationError("`backoff_factor` must be 1 or more.")

        # Accept any iterable of ints, but hold it as an immutable tuple so a
        # caller's list cannot mutate a live client's policy.
        object.__setattr__(self, "retryable_statuses", tuple(self.retryable_statuses))

    def to_dict(self) -> dict[str, Any]:
        return {
            "max_retries": self.max_retries,
            "initial_delay": self.initial_delay,
            "max_delay": self.max_delay,
            "backoff_factor": self.backoff_factor,
            "jitter": self.jitter,
            "retryable_statuses": list(self.retryable_statuses),
            "respect_retry_after": self.respect_retry_after,
        }


DEFAULT_RETRY = RetryOptions()
"""The retry policy used when none is supplied."""

RetryArgument = RetryOptions | Mapping[str, Any] | bool | None
"""
What the ``retry`` argument accepts.

``None`` keeps the current policy, ``False`` disables retrying, a
:class:`RetryOptions` replaces the policy outright, and a mapping merges its
keys onto the policy in force.
"""


@dataclass(frozen=True)
class ResolvedConfig:
    """Fully-resolved configuration, with the API key held separately."""

    base_url: str
    environment: PactmanEnvironment | None
    timeout: float
    retry: RetryOptions
    max_requests_per_second: float | None
    default_headers: dict[str, str] = field(default_factory=dict)
    user_agent: str = ""


def resolve_config(
    *,
    api_key: Any,
    environment: PactmanEnvironment | str | None = None,
    base_url: str | None = None,
    timeout: float | None = None,
    retry: RetryArgument = None,
    max_requests_per_second: float | None = None,
    default_headers: Mapping[str, str] | None = None,
) -> tuple[str, ResolvedConfig]:
    """
    Validates and resolves constructor options.

    :raises PactmanConfigurationError: for a missing or blank API key, an unknown
        environment, a malformed base URL, or nonsensical numeric options.
    """
    return (
        _validate_api_key(api_key),
        ResolvedConfig(
            base_url=_resolve_base_url(base_url, environment),
            environment=None if base_url is not None else _coerce_environment(environment),
            timeout=_resolve_timeout(timeout),
            retry=resolve_retry(DEFAULT_RETRY, retry),
            max_requests_per_second=_resolve_requests_per_second(max_requests_per_second),
            default_headers=dict(default_headers or {}),
            user_agent=build_user_agent(),
        ),
    )


def resolve_retry(current: RetryOptions, override: RetryArgument) -> RetryOptions:
    """Applies a ``retry`` argument to the policy currently in force."""
    if override is None:
        return current

    if override is False:
        return replace(current, max_retries=0)

    if override is True:
        return current

    if isinstance(override, RetryOptions):
        return override

    if isinstance(override, Mapping):
        unknown = set(override) - {f.name for f in RetryOptions.__dataclass_fields__.values()}

        if unknown:
            raise PactmanConfigurationError(
                f"Unknown retry option(s): {', '.join(sorted(unknown))}. "
                f"Valid keys: {', '.join(sorted(RetryOptions.__dataclass_fields__))}."
            )

        return replace(current, **dict(override))

    raise PactmanConfigurationError(
        "`retry` must be a RetryOptions, a mapping of overrides, False to "
        f"disable retrying, or None. Received {type(override).__name__}."
    )


def is_retryable_status(status: int, retry: RetryOptions) -> bool:
    """True when a status may be retried under ``retry``."""
    if status in _NEVER_RETRY_STATUSES:
        return False

    return status in retry.retryable_statuses


def build_user_agent() -> str:
    """``pactman-nonprofit-check-plus/<version> (python/<version>; <platform>)``"""
    return f"{PACKAGE_NAME}/{VERSION} (python/{platform.python_version()}; {sys.platform})"


def _validate_api_key(api_key: Any) -> str:
    if api_key is None:
        raise PactmanConfigurationError(
            "A Pactman API key is required. Pass `api_key`, for example from "
            "os.environ['PACTMAN_API_KEY']."
        )

    if not isinstance(api_key, str):
        raise PactmanConfigurationError(
            f"The Pactman API key must be a string, received {type(api_key).__name__}."
        )

    if api_key.strip() == "":
        raise PactmanConfigurationError(
            "The Pactman API key is empty. Check that the environment variable "
            "holding it is set."
        )

    return api_key.strip()


def _coerce_environment(environment: PactmanEnvironment | str | None) -> PactmanEnvironment:
    if environment is None:
        return DEFAULT_ENVIRONMENT

    try:
        return PactmanEnvironment(environment)
    except ValueError:
        supported = ", ".join(member.value for member in supported_environments())
        raise PactmanConfigurationError(
            f'Unknown environment "{environment}". Supported: {supported}. '
            "Use `base_url` to target a host that is not a named environment."
        ) from None


def _resolve_base_url(
    base_url: str | None, environment: PactmanEnvironment | str | None
) -> str:
    if base_url is not None:
        return _validate_base_url(base_url)

    return base_url_for_environment(_coerce_environment(environment))


def _validate_base_url(base_url: Any) -> str:
    if not isinstance(base_url, str) or base_url.strip() == "":
        raise PactmanConfigurationError("`base_url` must be a non-empty URL string.")

    parsed = urlsplit(base_url.strip())

    if parsed.scheme == "" or parsed.netloc == "":
        raise PactmanConfigurationError(
            f'`base_url` is not a valid URL: "{base_url}". Expected something '
            "like https://entities.pactman.org."
        )

    if parsed.scheme not in ("http", "https"):
        raise PactmanConfigurationError(
            f'`base_url` must use http or https, received "{parsed.scheme}".'
        )

    return f"{parsed.scheme}://{parsed.netloc}{parsed.path.rstrip('/')}"


def _resolve_timeout(timeout: Any) -> float:
    if timeout is None:
        return DEFAULT_TIMEOUT

    if isinstance(timeout, bool) or not isinstance(timeout, (int, float)):
        raise PactmanConfigurationError(
            "`timeout` must be a number of seconds greater than zero. There is "
            "no way to disable the timeout."
        )

    if not _is_finite(timeout) or timeout <= 0:
        raise PactmanConfigurationError(
            "`timeout` must be a number of seconds greater than zero. There is "
            "no way to disable the timeout."
        )

    return float(timeout)


def _resolve_requests_per_second(value: Any) -> float | None:
    if value is None:
        return None

    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise PactmanConfigurationError(
            "`max_requests_per_second` must be a number greater than zero, or omitted."
        )

    if not _is_finite(value) or value <= 0:
        raise PactmanConfigurationError(
            "`max_requests_per_second` must be a number greater than zero, or omitted."
        )

    return float(value)
