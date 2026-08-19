"""
The Pactman Nonprofit Check Plus client.

Server-side use only. The API key is a private credential; do not construct this
client anywhere the code or its configuration is shipped to an end user.
"""

from __future__ import annotations

from collections.abc import Iterable, Mapping, Sequence
from typing import Any, cast
from urllib.parse import quote

import httpx

from ._http import (
    AsyncTransport,
    Transport,
    TransportHooks,
    TransportResponse,
    normalize_api_errors,
)
from .config import ResolvedConfig, RetryArgument, resolve_config
from .ein import normalize_ein, normalize_eins
from .environments import (
    BULK_CHECK_PATH,
    MAX_BULK_EINS,
    SINGLE_CHECK_PATH,
    PactmanEnvironment,
)
from .errors import PactmanValidationError
from .types import (
    ApiEnvelope,
    ApiErrorDetail,
    BulkCheckResult,
    Nonprofit,
    SingleCheckResult,
)

__all__ = [
    "AsyncNonprofitsResource",
    "AsyncPactmanClient",
    "NonprofitsResource",
    "PactmanClient",
]


class NonprofitsResource:
    """Nonprofit lookups. Reached through :attr:`PactmanClient.nonprofits`."""

    def __init__(self, transport: Transport) -> None:
        self._transport = transport

    def check(
        self,
        ein: str,
        *,
        timeout: float | None = None,
        retry: RetryArgument = None,
        headers: Mapping[str, str] | None = None,
    ) -> SingleCheckResult:
        """
        Checks a single nonprofit by EIN.

        The EIN is normalized and validated locally first; a malformed EIN raises
        :class:`PactmanValidationError` without sending a request.

        >>> result = client.nonprofits.check("41-1787097")
        >>> result.nonprofit["organization_name"], result.check_count
        """
        return _shape_single(
            self._transport.send(
                method="GET",
                path=_single_path(ein),
                timeout=timeout,
                retry=retry,
                headers=headers,
            )
        )

    def check_bulk(
        self,
        eins: Sequence[str],
        *,
        dedupe: bool = False,
        timeout: float | None = None,
        retry: RetryArgument = None,
        headers: Mapping[str, str] | None = None,
    ) -> BulkCheckResult:
        """
        Checks up to :data:`MAX_BULK_EINS` nonprofits in one request.

        Every EIN is normalized and validated before anything is sent; if any one
        fails, the whole call raises :class:`PactmanValidationError` identifying
        the offending index, and no request is made. EINs are sent in the order
        supplied and duplicates are kept unless ``dedupe`` is set — but the API
        matches by set membership, so the response is not ordered to match and a
        repeated EIN comes back once. Index ``organizations`` by ``ein`` rather
        than pairing positionally.

        EINs the API has no record for are not an error: they arrive as HTTP 200
        with the missing values in ``not_found_eins``.

        >>> result = client.nonprofits.check_bulk(["41-1787097", "996589560"])
        >>> [org["ein"] for org in result.organizations]
        >>> result.not_found_eins
        """
        return _shape_bulk(
            self._transport.send(
                method="POST",
                path=BULK_CHECK_PATH,
                body=_bulk_payload(eins, dedupe=dedupe),
                timeout=timeout,
                retry=retry,
                headers=headers,
            )
        )


class AsyncNonprofitsResource:
    """Nonprofit lookups. Reached through :attr:`AsyncPactmanClient.nonprofits`."""

    def __init__(self, transport: AsyncTransport) -> None:
        self._transport = transport

    async def check(
        self,
        ein: str,
        *,
        timeout: float | None = None,
        retry: RetryArgument = None,
        headers: Mapping[str, str] | None = None,
    ) -> SingleCheckResult:
        """Checks a single nonprofit by EIN. See :meth:`NonprofitsResource.check`."""
        return _shape_single(
            await self._transport.send(
                method="GET",
                path=_single_path(ein),
                timeout=timeout,
                retry=retry,
                headers=headers,
            )
        )

    async def check_bulk(
        self,
        eins: Sequence[str],
        *,
        dedupe: bool = False,
        timeout: float | None = None,
        retry: RetryArgument = None,
        headers: Mapping[str, str] | None = None,
    ) -> BulkCheckResult:
        """Checks up to :data:`MAX_BULK_EINS` nonprofits in one request.

        See :meth:`NonprofitsResource.check_bulk`.
        """
        return _shape_bulk(
            await self._transport.send(
                method="POST",
                path=BULK_CHECK_PATH,
                body=_bulk_payload(eins, dedupe=dedupe),
                timeout=timeout,
                retry=retry,
                headers=headers,
            )
        )


class _ClientBase:
    """Configuration, redaction and lifecycle shared by both clients."""

    _config: ResolvedConfig
    _owns_client: bool

    @property
    def base_url(self) -> str:
        """The resolved base URL every request is sent to."""
        return self._config.base_url

    @property
    def environment(self) -> PactmanEnvironment | None:
        """The named environment in use, or ``None`` when an explicit ``base_url`` was given."""
        return self._config.environment

    @property
    def timeout(self) -> float:
        """The resolved timeout per attempt, in seconds."""
        return self._config.timeout

    def to_dict(self) -> dict[str, Any]:
        """
        A redacted view of the configuration.

        The API key is not an attribute of this object and never appears here or
        in ``repr()``.
        """
        return {
            "base_url": self._config.base_url,
            "environment": (
                self._config.environment.value if self._config.environment else None
            ),
            "timeout": self._config.timeout,
            "retry": self._config.retry.to_dict(),
            "max_requests_per_second": self._config.max_requests_per_second,
            "user_agent": self._config.user_agent,
            "api_key": "[redacted]",
        }

    def __repr__(self) -> str:
        return f"{type(self).__name__}(base_url={self._config.base_url!r})"


class PactmanClient(_ClientBase):
    """
    Entry point for the SDK.

    >>> client = PactmanClient(api_key=os.environ["PACTMAN_API_KEY"])
    >>> result = client.nonprofits.check("41-1787097")

    Use it as a context manager, or call :meth:`close`, so the underlying
    connection pool is released::

        with PactmanClient(api_key=key) as client:
            client.nonprofits.check("41-1787097")
    """

    def __init__(
        self,
        api_key: str | None = None,
        *,
        environment: PactmanEnvironment | str | None = None,
        base_url: str | None = None,
        timeout: float | None = None,
        retry: RetryArgument = None,
        max_requests_per_second: float | None = None,
        default_headers: Mapping[str, str] | None = None,
        http_client: httpx.Client | None = None,
        _hooks: TransportHooks | None = None,
    ) -> None:
        """
        :param api_key: Your Pactman API key. Load it from the environment or a
            secret manager; never commit it, and never ship it to an end user.
        :param environment: Named Pactman environment. Defaults to production.
        :param base_url: Explicit base URL, for a mock server, a proxy, or a host
            Pactman has given you directly. Overrides ``environment`` when set.
        :param timeout: Timeout per attempt, in seconds. Defaults to 30.
        :param retry: Retry policy, or ``False`` to disable retrying entirely.
        :param max_requests_per_second: Optional client-side ceiling on outbound
            requests per second. Off by default; the server's limits are
            authoritative and may change.
        :param default_headers: Extra headers sent with every request. Cannot
            override ``Authorization``.
        :param http_client: An ``httpx.Client`` to send through. Supply one to
            reuse a pool, set proxies or pin certificates. A supplied client is
            never closed by this SDK.
        :param _hooks: Internal seam for injecting a clock in tests. Not covered
            by semantic versioning; do not depend on it.
        """
        key, config = resolve_config(
            api_key=api_key,
            environment=environment,
            base_url=base_url,
            timeout=timeout,
            retry=retry,
            max_requests_per_second=max_requests_per_second,
            default_headers=default_headers,
        )

        self._config = config
        self._owns_client = http_client is None
        self._client = http_client or httpx.Client(follow_redirects=True)
        self.nonprofits = NonprofitsResource(Transport(key, config, self._client, _hooks))

    def close(self) -> None:
        """Releases the connection pool, unless the client was supplied by the caller."""
        if self._owns_client:
            self._client.close()

    def __enter__(self) -> PactmanClient:
        return self

    def __exit__(self, *exc_info: object) -> None:
        self.close()


class AsyncPactmanClient(_ClientBase):
    """
    Async entry point for the SDK.

    >>> async with AsyncPactmanClient(api_key=key) as client:
    ...     result = await client.nonprofits.check("41-1787097")

    Identical behaviour to :class:`PactmanClient`; only the call style differs.
    Cancelling the surrounding task cancels the request and any planned retries.
    """

    def __init__(
        self,
        api_key: str | None = None,
        *,
        environment: PactmanEnvironment | str | None = None,
        base_url: str | None = None,
        timeout: float | None = None,
        retry: RetryArgument = None,
        max_requests_per_second: float | None = None,
        default_headers: Mapping[str, str] | None = None,
        http_client: httpx.AsyncClient | None = None,
        _hooks: TransportHooks | None = None,
    ) -> None:
        """See :class:`PactmanClient` for the parameters."""
        key, config = resolve_config(
            api_key=api_key,
            environment=environment,
            base_url=base_url,
            timeout=timeout,
            retry=retry,
            max_requests_per_second=max_requests_per_second,
            default_headers=default_headers,
        )

        self._config = config
        self._owns_client = http_client is None
        self._client = http_client or httpx.AsyncClient(follow_redirects=True)
        self.nonprofits = AsyncNonprofitsResource(
            AsyncTransport(key, config, self._client, _hooks)
        )

    async def aclose(self) -> None:
        """Releases the connection pool, unless the client was supplied by the caller."""
        if self._owns_client:
            await self._client.aclose()

    async def __aenter__(self) -> AsyncPactmanClient:
        return self

    async def __aexit__(self, *exc_info: object) -> None:
        await self.aclose()


def _single_path(ein: str) -> str:
    return SINGLE_CHECK_PATH.replace("{ein}", quote(normalize_ein(ein), safe=""))


def _bulk_payload(eins: Sequence[str], *, dedupe: bool) -> list[str]:
    if isinstance(eins, (str, bytes)):
        raise PactmanValidationError(
            "check_bulk expects a sequence of EIN strings, received "
            f"{type(eins).__name__}. Pass a list such as ['411787097'], or use "
            "check() for a single EIN."
        )

    if isinstance(eins, Mapping) or not isinstance(eins, Iterable):
        raise PactmanValidationError(
            "check_bulk expects a sequence of EIN strings, received "
            f"{type(eins).__name__}."
        )

    # Materialize once so validation and serialization see identical input.
    supplied = list(eins)

    if not supplied:
        raise PactmanValidationError("check_bulk requires at least one EIN.")

    normalized = normalize_eins(supplied)
    payload = list(dict.fromkeys(normalized)) if dedupe else normalized

    if len(payload) > MAX_BULK_EINS:
        raise PactmanValidationError(
            f"check_bulk accepts at most {MAX_BULK_EINS} EINs per request, "
            f"received {len(payload)}. Split the input into batches; this SDK "
            "does not chunk automatically."
        )

    return payload


def _base_fields(response: TransportResponse) -> dict[str, Any]:
    envelope: ApiEnvelope = response.body if isinstance(response.body, dict) else {}

    return {
        "check_count": _as_number(envelope.get("nonprofit_check_count")),
        "time_taken_ms": _as_number(envelope.get("timeTaken")),
        "errors": normalize_api_errors(envelope.get("errors")),
        "request_id": response.request_id,
        "status": response.status,
        "raw": response.body,
    }


def _shape_single(response: TransportResponse) -> SingleCheckResult:
    envelope = response.body if isinstance(response.body, dict) else {}

    return SingleCheckResult(
        **_base_fields(response), nonprofit=_extract_nonprofit(envelope.get("data"))
    )


def _shape_bulk(response: TransportResponse) -> BulkCheckResult:
    envelope = response.body if isinstance(response.body, dict) else {}
    base = _base_fields(response)

    return BulkCheckResult(
        **base,
        organizations=_extract_organizations(envelope.get("data")),
        not_found_eins=_extract_not_found_eins(base["errors"]),
    )


def _extract_nonprofit(data: Any) -> Nonprofit | None:
    if data is None:
        return None

    if isinstance(data, list):
        return cast(Nonprofit, data[0]) if data and isinstance(data[0], dict) else None

    return cast(Nonprofit, data) if isinstance(data, dict) else None


def _extract_organizations(data: Any) -> list[Nonprofit]:
    """
    The published schema returns ``data`` as an array. Some deployments wrap it
    as ``{"organizations": [...]}``, so both are accepted rather than silently
    yielding an empty list.
    """
    if isinstance(data, list):
        return _records(data)

    if isinstance(data, dict):
        wrapped = data.get("organizations")

        if isinstance(wrapped, list):
            return _records(wrapped)

    return []


def _records(entries: list[Any]) -> list[Nonprofit]:
    return [cast(Nonprofit, entry) for entry in entries if isinstance(entry, dict)]


def _extract_not_found_eins(errors: list[ApiErrorDetail]) -> list[str]:
    found: list[str] = []

    for detail in errors:
        eins = detail.get("eins")

        if isinstance(eins, list):
            found.extend(entry for entry in eins if isinstance(entry, str))
        elif isinstance(eins, str):
            found.extend(part.strip() for part in eins.split(",") if part.strip() != "")

    return found


def _as_number(value: Any) -> Any:
    """Numbers only — ``True`` is an ``int`` in Python and must not slip through."""
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return None

    return value
