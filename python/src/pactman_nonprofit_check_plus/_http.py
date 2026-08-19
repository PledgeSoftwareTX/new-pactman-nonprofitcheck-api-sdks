"""
HTTP transport: authentication headers, timeouts, retries with jittered backoff,
``Retry-After`` handling, and mapping responses to the error taxonomy.

The API key is written into the ``Authorization`` header at send time and is
never stored on a request record, an error, or any diagnostic output.

Internal module. Nothing here is part of the public API.
"""

from __future__ import annotations

import asyncio
import json
import random as _random
import threading
import time
from collections.abc import Callable, Mapping
from dataclasses import dataclass
from email.utils import parsedate_to_datetime
from typing import Any, cast

import httpx

from .config import (
    ResolvedConfig,
    RetryArgument,
    RetryOptions,
    is_retryable_status,
    resolve_retry,
)
from .errors import (
    PactmanApiError,
    PactmanApiErrorInit,
    PactmanError,
    PactmanNetworkError,
    PactmanTimeoutError,
    error_from_status,
)
from .types import ApiEnvelope, ApiErrorDetail


@dataclass
class TransportHooks:
    """
    Seam for injecting a clock into tests. Not part of the public API and not
    covered by semantic versioning; do not depend on it.
    """

    sleep: Callable[[float], Any] | None = None
    """Blocking on the sync transport, awaitable on the async one."""

    random: Callable[[], float] | None = None
    """Returns a value in ``[0, 1)``. Used for backoff jitter."""

    monotonic: Callable[[], float] | None = None
    """Returns a monotonically increasing time in seconds. Used for throttling."""


@dataclass(frozen=True)
class TransportResponse:
    """A parsed HTTP response plus the metadata callers need."""

    status: int
    request_id: str | None
    body: ApiEnvelope | str | None
    attempts: int


@dataclass(frozen=True)
class _Attempt:
    """The outcome of one HTTP attempt."""

    response: httpx.Response | None = None
    parsed: ApiEnvelope | str | None = None
    error: PactmanError | None = None
    cause: BaseException | None = None


@dataclass(frozen=True)
class _Plan:
    """Everything an attempt loop needs, computed once per ``send``."""

    url: str
    headers: dict[str, str]
    content: bytes | None
    timeout: float
    retry: RetryOptions


class _BaseTransport:
    """Shared state and pure helpers for the sync and async transports."""

    def __init__(
        self,
        api_key: str,
        config: ResolvedConfig,
        hooks: TransportHooks | None = None,
    ) -> None:
        self._api_key = api_key
        self._config = config
        hooks = hooks or TransportHooks()
        self._random = hooks.random or _random.random
        self._monotonic = hooks.monotonic or time.monotonic
        self._sleep_hook = hooks.sleep
        self._next_request_at = 0.0

    def _plan(
        self,
        *,
        path: str,
        body: Any,
        timeout: float | None,
        retry: RetryArgument,
        headers: Mapping[str, str] | None,
    ) -> _Plan:
        return _Plan(
            url=f"{self._config.base_url}{path}",
            headers=self._build_headers(headers, body is not None),
            content=None if body is None else json.dumps(body).encode("utf-8"),
            timeout=self._config.timeout if timeout is None else timeout,
            retry=resolve_retry(self._config.retry, retry),
        )

    def _build_headers(
        self, per_request: Mapping[str, str] | None, has_body: bool
    ) -> dict[str, str]:
        headers: dict[str, str] = {**self._config.default_headers, **(per_request or {})}

        # Set last so neither the client defaults nor a per-request header can
        # displace the credential or misdeclare the payload.
        headers["Accept"] = "application/json"
        headers["User-Agent"] = self._config.user_agent
        headers["Authorization"] = f"Bearer {self._api_key}"

        if has_body:
            headers["Content-Type"] = "application/json"

        return headers

    def _classify(
        self, exc: BaseException, *, timeout: float, attempt: int
    ) -> _Attempt:
        if isinstance(exc, httpx.TimeoutException):
            return _Attempt(
                error=PactmanTimeoutError(
                    f"The request timed out after {timeout}s.", timeout, attempt
                ),
                cause=exc,
            )

        return _Attempt(
            error=PactmanNetworkError(
                f"The request to the Pactman API failed: {exc}", attempt
            ),
            cause=exc,
        )

    def _succeeded(self, attempt: _Attempt, attempts: int) -> TransportResponse:
        assert attempt.response is not None
        return TransportResponse(
            status=attempt.response.status_code,
            request_id=read_request_id(attempt.response.headers),
            body=attempt.parsed,
            attempts=attempts,
        )

    def _api_error(
        self, attempt: _Attempt, attempts: int
    ) -> tuple[PactmanApiError, float | None]:
        assert attempt.response is not None
        retry_after = read_retry_after(attempt.response.headers)

        error = error_from_status(
            build_api_error_init(
                status=attempt.response.status_code,
                parsed=attempt.parsed,
                request_id=read_request_id(attempt.response.headers),
                retry_after_seconds=retry_after,
                attempts=attempts,
            )
        )

        return error, retry_after

    def _next_throttle_delay(self) -> float:
        """Seconds to wait before the next request, honoring ``max_requests_per_second``."""
        limit = self._config.max_requests_per_second

        if limit is None:
            return 0.0

        interval = 1.0 / limit
        now = self._monotonic()
        scheduled_at = max(now, self._next_request_at)
        self._next_request_at = scheduled_at + interval

        return max(0.0, scheduled_at - now)

    def _retry_delay(
        self, attempt: int, retry: RetryOptions, retry_after_seconds: float | None
    ) -> float:
        return compute_retry_delay(attempt, retry, retry_after_seconds, self._random)


class Transport(_BaseTransport):
    """Issues authenticated requests against the Pactman API, synchronously."""

    def __init__(
        self,
        api_key: str,
        config: ResolvedConfig,
        client: httpx.Client,
        hooks: TransportHooks | None = None,
    ) -> None:
        super().__init__(api_key, config, hooks)
        self._client = client
        self._throttle_lock = threading.Lock()

    def send(
        self,
        *,
        method: str,
        path: str,
        body: Any = None,
        timeout: float | None = None,
        retry: RetryArgument = None,
        headers: Mapping[str, str] | None = None,
    ) -> TransportResponse:
        plan = self._plan(
            path=path, body=body, timeout=timeout, retry=retry, headers=headers
        )
        attempts = 0

        while True:
            attempts += 1
            self._throttle()
            outcome = self._attempt(method, plan, attempts)

            if outcome.response is not None:
                if outcome.response.is_success:
                    return self._succeeded(outcome, attempts)

                error, retry_after = self._api_error(outcome, attempts)

                if attempts > plan.retry.max_retries or not is_retryable_status(
                    outcome.response.status_code, plan.retry
                ):
                    raise error

                self._sleep(self._retry_delay(attempts, plan.retry, retry_after))
                continue

            # A timeout or transport failure.
            assert outcome.error is not None

            if attempts > plan.retry.max_retries:
                raise outcome.error from outcome.cause

            self._sleep(self._retry_delay(attempts, plan.retry, None))

    def _attempt(self, method: str, plan: _Plan, attempt: int) -> _Attempt:
        try:
            response = self._client.request(
                method,
                plan.url,
                headers=plan.headers,
                content=plan.content,
                timeout=plan.timeout,
            )
        except Exception as exc:
            return self._classify(exc, timeout=plan.timeout, attempt=attempt)

        return _Attempt(response=response, parsed=parse_body(response))

    def _throttle(self) -> None:
        with self._throttle_lock:
            delay = self._next_throttle_delay()

        if delay > 0:
            self._sleep(delay)

    def _sleep(self, seconds: float) -> None:
        if self._sleep_hook is not None:
            self._sleep_hook(seconds)
            return

        time.sleep(seconds)


class AsyncTransport(_BaseTransport):
    """Issues authenticated requests against the Pactman API, asynchronously."""

    def __init__(
        self,
        api_key: str,
        config: ResolvedConfig,
        client: httpx.AsyncClient,
        hooks: TransportHooks | None = None,
    ) -> None:
        super().__init__(api_key, config, hooks)
        self._client = client
        self._throttle_lock = asyncio.Lock()

    async def send(
        self,
        *,
        method: str,
        path: str,
        body: Any = None,
        timeout: float | None = None,
        retry: RetryArgument = None,
        headers: Mapping[str, str] | None = None,
    ) -> TransportResponse:
        plan = self._plan(
            path=path, body=body, timeout=timeout, retry=retry, headers=headers
        )
        attempts = 0

        while True:
            attempts += 1
            await self._throttle()
            outcome = await self._attempt(method, plan, attempts)

            if outcome.response is not None:
                if outcome.response.is_success:
                    return self._succeeded(outcome, attempts)

                error, retry_after = self._api_error(outcome, attempts)

                if attempts > plan.retry.max_retries or not is_retryable_status(
                    outcome.response.status_code, plan.retry
                ):
                    raise error

                await self._sleep(self._retry_delay(attempts, plan.retry, retry_after))
                continue

            assert outcome.error is not None

            if attempts > plan.retry.max_retries:
                raise outcome.error from outcome.cause

            await self._sleep(self._retry_delay(attempts, plan.retry, None))

    async def _attempt(self, method: str, plan: _Plan, attempt: int) -> _Attempt:
        try:
            response = await self._client.request(
                method,
                plan.url,
                headers=plan.headers,
                content=plan.content,
                timeout=plan.timeout,
            )
        except Exception as exc:
            return self._classify(exc, timeout=plan.timeout, attempt=attempt)

        return _Attempt(response=response, parsed=parse_body(response))

    async def _throttle(self) -> None:
        async with self._throttle_lock:
            delay = self._next_throttle_delay()

        if delay > 0:
            await self._sleep(delay)

    async def _sleep(self, seconds: float) -> None:
        if self._sleep_hook is not None:
            result = self._sleep_hook(seconds)

            if asyncio.iscoroutine(result):
                await result

            return

        await asyncio.sleep(seconds)


def compute_retry_delay(
    attempt: int,
    retry: RetryOptions,
    retry_after_seconds: float | None,
    random: Callable[[], float] = _random.random,
) -> float:
    """
    Delay before the next attempt, in seconds.

    A valid ``Retry-After`` wins outright. Otherwise the delay grows
    exponentially from ``initial_delay``, is capped at ``max_delay``, and — with
    jitter on — is randomized across the whole range so concurrent clients
    spread out.
    """
    honors_server = (
        retry.respect_retry_after
        and retry_after_seconds is not None
        and retry_after_seconds >= 0
    )

    if honors_server:
        assert retry_after_seconds is not None
        return round(retry_after_seconds, 3)

    exponential = retry.initial_delay * retry.backoff_factor ** (attempt - 1)
    capped = min(exponential, retry.max_delay)

    return round(random() * capped if retry.jitter else capped, 3)


def read_retry_after(headers: httpx.Headers, now: float | None = None) -> float | None:
    """Reads ``Retry-After`` as either a delay in seconds or an HTTP date."""
    raw = headers.get("retry-after")

    if raw is None:
        return None

    trimmed = raw.strip()

    if trimmed == "":
        return None

    try:
        seconds = float(trimmed)
    except ValueError:
        pass
    else:
        return seconds if seconds >= 0 else None

    try:
        parsed = parsedate_to_datetime(trimmed)
    except (TypeError, ValueError):
        return None

    reference = time.time() if now is None else now

    return max(0.0, parsed.timestamp() - reference)


def normalize_api_errors(errors: Any) -> list[ApiErrorDetail]:
    """Normalizes the envelope's ``errors`` into a list."""
    if errors is None:
        return []

    if isinstance(errors, list):
        return [cast(ApiErrorDetail, entry) for entry in errors if isinstance(entry, dict)]

    if isinstance(errors, str):
        return [] if errors.strip() == "" else [{"reason": errors}]

    if isinstance(errors, dict):
        return [cast(ApiErrorDetail, errors)]

    return []


def build_api_error_init(
    *,
    status: int,
    parsed: ApiEnvelope | str | None,
    request_id: str | None,
    retry_after_seconds: float | None,
    attempts: int,
) -> PactmanApiErrorInit:
    """Collects the response metadata an API error carries."""
    envelope = parsed if isinstance(parsed, dict) else None
    api_errors = normalize_api_errors(envelope.get("errors") if envelope else None)

    reasons = [
        reason
        for reason in (detail.get("reason") for detail in api_errors)
        if isinstance(reason, str) and reason.strip() != ""
    ]

    envelope_message = envelope.get("message") if envelope else None
    api_code = envelope.get("code") if envelope else None

    if reasons:
        api_message: str | None = "; ".join(reasons)
    elif isinstance(envelope_message, str):
        api_message = envelope_message
    elif isinstance(parsed, str) and parsed.strip() != "":
        api_message = parsed.strip()[:500]
    else:
        api_message = None

    return PactmanApiErrorInit(
        status=status,
        api_message=api_message,
        api_code=api_code if isinstance(api_code, int) else None,
        api_errors=api_errors,
        request_id=request_id,
        retry_after_seconds=retry_after_seconds,
        raw=parsed,
        attempts=attempts,
    )


def parse_body(response: httpx.Response) -> ApiEnvelope | str | None:
    """Parses a response body, preserving unparseable text as evidence."""
    try:
        text = response.text
    except Exception:
        return None

    if text.strip() == "":
        return None

    try:
        return cast("ApiEnvelope | str", json.loads(text))
    except ValueError:
        return text


def read_request_id(headers: httpx.Headers) -> str | None:
    """Reads the correlation identifier from the response headers."""
    for name in ("x-request-id", "x-correlation-id", "request-id"):
        value = headers.get(name)

        if value is not None:
            return str(value)

    return None
