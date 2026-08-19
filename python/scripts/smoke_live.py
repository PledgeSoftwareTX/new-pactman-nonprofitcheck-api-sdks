#!/usr/bin/env python
"""
Contract smoke test against a live Nonprofit Check Plus deployment.

The mock server in ``mock_server.py`` proves the SDK behaves against a stub the
SDK's own authors wrote. This proves it behaves against the real thing.

Coverage tracks the documented examples: every claim ``examples/ex_01`` through
``examples/ex_30`` makes about the live API has a check here. Most of them cost
nothing — a claim about the shape of a record is answered by a record already
fetched, and a claim about local validation is answered without sending
anything. Only a handful of checks need their own round trip.

The report is grouped the same way: one heading per example file, and under it
the checks that stand behind what that file claims. Checks run in dependency
order rather than example order — a record has to be fetched before anything can
be asserted about it, and the log of what went on the wire is only complete at
the end — so nothing prints until the run is over. The ticker is what says it is
alive in the meantime.

IT SPENDS REAL QUOTA. Every billable check is charged against the account behind
the key. There is nothing to configure and nothing to opt into: one command runs
the whole plan, the disruptive probes included, and what it will cost is printed
as it starts.

Usage
    python scripts/smoke_live.py

That is the whole interface. The key is read from PACTMAN_API_KEY, in the
environment or in ``python/.env``; PACTMAN_BASE_URL aims the run at a deployment
other than production, which is how it is run against the mock server.
"""

from __future__ import annotations

import asyncio
import json
import math
import os
import re
import sys
import time
from collections.abc import Callable, Mapping, Sequence
from dataclasses import dataclass, field
from datetime import datetime, timedelta
from enum import Enum
from pathlib import Path
from typing import Any, cast

import httpx
from contract import (
    Diff,
    format_changes,
    schema_diff,
    signature_of,
    summarize_changes,
    type_diff,
)
from fixtures import KNOWN_NONPROFIT_FIELDS

import pactman_nonprofit_check_plus as sdk
from pactman_nonprofit_check_plus import (
    BULK_CHECK_PATH,
    DEFAULT_ENVIRONMENT,
    DEFAULT_TIMEOUT,
    EIN_LENGTH,
    MAX_BULK_EINS,
    SINGLE_CHECK_PATH,
    VERSION,
    AsyncPactmanClient,
    Nonprofit,
    PactmanApiError,
    PactmanApiErrorInit,
    PactmanAuthenticationError,
    PactmanAuthorizationError,
    PactmanBadRequestError,
    PactmanClient,
    PactmanConfigurationError,
    PactmanError,
    PactmanErrorCategory,
    PactmanErrorOrigin,
    PactmanNetworkError,
    PactmanNotFoundError,
    PactmanRateLimitError,
    PactmanServerError,
    PactmanTimeoutError,
    PactmanValidationError,
    RetryOptions,
    base_url_for_environment,
    get_aroe,
    get_bmf,
    get_ofac,
    get_pub78,
    is_pactman_error,
    is_valid_ein,
    normalize_ein,
    normalize_eins,
    supported_environments,
)

ROOT = Path(__file__).resolve().parents[1]

# The organizations this harness checks.
#
# A primary subject with a record, a second one to give the bulk order and
# duplicate probes something to work with, and a well-formed EIN with no record
# for the not-found and partial-success paths. They are the test data in the test
# plan, and the first two are reachable on a free-tier key, so a free key gets as
# far as a free key can.
EIN = "996589560"
BULK_EINS = ["996589560", "680343125"]
MISSING_EIN = "999999999"

# The variable the credential is read from, in the environment or in `.env`.
API_KEY_ENV = "PACTMAN_API_KEY"

# Sent where a key is meant to be rejected. Synthetic, so it cannot be valid.
INVALID_API_KEY = "pactman-smoke-test-invalid-key"

# Ceiling on the burst the rate-limit probe is allowed to send.
RATE_LIMIT_ATTEMPTS = 10

STATUS = {"pass": "✓", "fail": "✗", "warn": "!", "skip": "\u2013"}


# --- environment file --------------------------------------------------------


@dataclass(frozen=True)
class EnvFile:
    """A loaded ``.env``, and which names it supplied."""

    path: Path
    names: set[str]


def load_env_file() -> EnvFile | None:
    """
    Loads ``python/.env``, so the key and any standing overrides live in a file
    rather than in the shell for every run. The file is gitignored.

    A variable already in the environment wins: exporting one for a single run
    must not be silently overridden by a file someone set up months ago.
    """
    path = ROOT / ".env"

    if not path.exists():
        return None

    pattern = re.compile(r"^\s*(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)$")
    names: set[str] = set()

    for line in path.read_text(encoding="utf-8").splitlines():
        matched = pattern.match(line)

        if not matched or matched.group(1) in os.environ:
            continue

        name, raw = matched.group(1), matched.group(2).strip()

        if len(raw) >= 2 and raw[0] == raw[-1] and raw[0] in "'\"":
            raw = raw[1:-1]

        os.environ[name] = raw
        names.add(name)

    return EnvFile(path=path, names=names)


# --- secret handling ---------------------------------------------------------

_SECRETS: set[str] = set()


def redact(value: object) -> str:
    """Replaces every known credential with a placeholder. Applied to all output."""
    text = value if isinstance(value, str) else repr(value)

    for secret in _SECRETS:
        if len(secret) >= 4:
            text = text.replace(secret, "[redacted]")

    return text


def say(text: str = "") -> None:
    print(redact(text))


def key_source(env_file: EnvFile | None) -> str:
    """Where the credential came from, named precisely enough to correct."""
    if env_file is not None and API_KEY_ENV in env_file.names:
        return f"{API_KEY_ENV} in {env_file.path.name}"

    return API_KEY_ENV


# --- the examples this harness answers for -----------------------------------

EXAMPLES_DIR = ROOT / "examples"

# The checks that are not answering for an example file. The response contract is
# the API's own shape held against a recording of it — drift there is not
# something any example claims, and it gets its own heading rather than being
# filed under one.
CONTRACT_GROUP_ID = "contract"
CONTRACT_GROUP_TITLE = "the live response held against the recorded baseline"

_TITLE = re.compile(r"^EX-\d{2}\s+—\s+(.+?)\.?\s*$", re.MULTILINE)
_NUMBERED = re.compile(r"^ex_\d{2}_")

# Reading order for the unnumbered originals; anything else follows, by name.
ORIGINALS = ("quickstart", "bulk", "error_handling", "async_concurrent")


@dataclass(frozen=True)
class Example:
    """One ``examples/ex_NN_*.py``, as the report heads it."""

    id: str
    title: str


def title_of(path: Path, fallback: str) -> str:
    """The title a file gives itself: its ``EX-NN —`` line, or its opening sentence."""
    try:
        header = path.read_text(encoding="utf-8")[:600]
    except OSError:
        return fallback

    titled = _TITLE.search(header)

    if titled:
        return titled.group(1)

    for line in header.splitlines():
        text = line.strip().strip('"').strip()

        if text:
            return text.rstrip(".")

    return fallback


def discover_examples() -> list[Example]:
    """
    Every example in ``examples/``, in reading order, with the title it gives
    itself.

    The unnumbered originals come first: ``quickstart``, ``bulk``,
    ``error_handling`` and ``async_concurrent`` are the shortest form of what the
    numbered files elaborate, and they are what anyone runs before anything else,
    so they are what the report opens with.

    Read from disk rather than listed here, so an example added tomorrow appears
    in the report on its own — with no check under it, which is the state worth
    seeing.
    """
    files = [path for path in EXAMPLES_DIR.glob("*.py") if not path.name.startswith("_")]
    numbered = sorted(path for path in files if _NUMBERED.match(path.name))
    originals = sorted(
        (path for path in files if not _NUMBERED.match(path.name)),
        key=lambda path: (
            ORIGINALS.index(path.stem) if path.stem in ORIGINALS else len(ORIGINALS),
            path.stem,
        ),
    )

    return [
        Example(id=path.stem, title=title_of(path, path.stem.replace("_", " ")))
        for path in originals
    ] + [
        Example(
            id=f"ex-{path.stem[3:5]}", title=title_of(path, path.stem[6:].replace("_", " "))
        )
        for path in numbered
    ]


@dataclass
class Group:
    """A heading in the report, and the results filed under it."""

    id: str
    title: str
    primary: list[Result] = field(default_factory=list)
    secondary: list[tuple[Result, str]] = field(default_factory=list)


def group_by_example(examples: Sequence[Example], results: Sequence[Result]) -> list[Group]:
    """
    The headings, in reading order, with every check filed under the examples it
    covers.

    A check is listed in full under the first example it covers and cross-
    referenced under the rest: it ran once, so it is counted once, but an example
    whose claim is proven by a check that lives elsewhere still says so under its
    own heading rather than looking untested.
    """
    groups: dict[str, Group] = {
        example.id: Group(id=example.id, title=example.title) for example in examples
    }
    groups[CONTRACT_GROUP_ID] = Group(id=CONTRACT_GROUP_ID, title=CONTRACT_GROUP_TITLE)

    def group_for(name: str) -> Group:
        # A check naming something the examples directory does not have. Give it a
        # heading anyway; a result must never fall out of the report.
        if name not in groups:
            groups[name] = Group(id=name, title="no example file of this name")

        return groups[name]

    for result in results:
        group_for(result.covers[0]).primary.append(result)

        for other in result.covers[1:]:
            group_for(other).secondary.append((result, result.covers[0]))

    return list(groups.values())


# --- the runner --------------------------------------------------------------


class CheckFailedError(Exception):
    """Raised by a check that found what it was looking for to be untrue."""


def check_that(condition: bool, message: str) -> None:
    if not condition:
        raise CheckFailedError(message)


@dataclass(frozen=True)
class Outcome:
    """What a check has to say when it did not raise."""

    status: str = "pass"
    detail: str = ""
    data: Any = None


@dataclass(frozen=True)
class Check:
    """One entry in the plan."""

    covers: tuple[str, ...]
    name: str
    cost: int
    body: Callable[[Runner], Outcome]


@dataclass(frozen=True)
class Result:
    """What running one check produced."""

    covers: tuple[str, ...]
    name: str
    status: str
    detail: str
    cost: int
    duration_ms: int


@dataclass(frozen=True)
class Finding:
    """An observation that is informative but not a pass or a fail."""

    check: str
    message: str


@dataclass(frozen=True)
class SentRequest:
    """One outbound request, with the credential reduced to a flag."""

    method: str
    url: str
    url_carries_key: bool
    auth_carries_key: bool
    auth_scheme: str
    accept: str | None
    content_type: str | None
    user_agent: str | None
    body: str | None


class Runner:
    """Holds the client, what the run has spent, and what it has learned."""

    client: PactmanClient

    def __init__(self, api_key: str) -> None:
        self.api_key = api_key
        self.results: list[Result] = []
        self.findings: list[Finding] = []
        self.requests: list[SentRequest] = []
        self.checks_spent = 0
        self.requests_sent = 0
        self.cycle_count_start: int | None = None
        self.cycle_count_end: int | None = None
        self.single_result: Any = None
        self.bulk_result: Any = None
        self.bulk_submitted: list[str] = []
        self.free_tier_key = False
        self.observed_round_trip: float | None = None

    def note(self, check: str, message: str) -> None:
        """Records an observation that is informative but not a pass/fail."""
        self.findings.append(Finding(check=check, message=message))

    def record_request(self, request: httpx.Request) -> None:
        """
        Captures what went on the wire. The Authorization value is reduced to a
        boolean here rather than stored, so no code path downstream can print it.
        """
        self.requests_sent += 1

        url = str(request.url)
        authorization = request.headers.get("authorization", "")
        body = request.content.decode("utf-8", "replace") if request.content else None

        self.requests.append(
            SentRequest(
                method=request.method,
                url=url,
                url_carries_key=self.api_key in url,
                auth_carries_key=self.api_key in authorization,
                auth_scheme=authorization.split(" ")[0] if authorization else "",
                accept=request.headers.get("accept"),
                content_type=request.headers.get("content-type"),
                user_agent=request.headers.get("user-agent"),
                body=body,
            )
        )

    def capture_bulk(self, result: Any, submitted: Sequence[str]) -> None:
        """
        Keeps the first successful bulk response for the checks that read one.

        ``bulk partial success`` is the better subject — its envelope is the only
        one carrying the item-level errors a batch with a miss returns — but it is
        unreachable on a key whose bulk EINs are allowlisted, since such a key
        refuses the whole batch. Capturing here rather than in that one check
        means the duplicate probe's response stands in when it has to, instead of
        four later checks skipping for want of any bulk response at all.
        """
        if self.bulk_result is None:
            self.bulk_result = result
            self.bulk_submitted = list(submitted)

    def observe_cycle_count(self, value: Any) -> None:
        """Tracks the cumulative counter across the whole run."""
        if not isinstance(value, int) or isinstance(value, bool):
            return

        if self.cycle_count_start is None:
            self.cycle_count_start = value

        self.cycle_count_end = value

    def run(self, check: Check) -> None:
        started = time.monotonic()

        try:
            outcome = check.body(self)
            status, detail = outcome.status, outcome.detail
        except Exception as error:
            # A failed check may still have been billed, so the cost stands.
            status = "fail"
            detail = redact(str(error) or type(error).__name__)

        self.checks_spent += check.cost
        self.results.append(
            Result(
                covers=check.covers,
                name=check.name,
                status=status,
                detail=detail,
                cost=check.cost,
                duration_ms=round((time.monotonic() - started) * 1000),
            )
        )


class RecordingTransport(httpx.BaseTransport):
    """The real transport, with every outbound request written to the log first."""

    def __init__(self, runner: Runner) -> None:
        self._runner = runner
        self._inner = httpx.HTTPTransport()

    def handle_request(self, request: httpx.Request) -> httpx.Response:
        self._runner.record_request(request)

        return self._inner.handle_request(request)

    def close(self) -> None:
        self._inner.close()


class CountingTransport(httpx.BaseTransport):
    """The real transport, counting attempts at the socket rather than at the SDK."""

    def __init__(self) -> None:
        self.sent = 0
        self._inner = httpx.HTTPTransport()

    def handle_request(self, request: httpx.Request) -> httpx.Response:
        self.sent += 1

        return self._inner.handle_request(request)

    def close(self) -> None:
        self._inner.close()


class ReachedTransportError(Exception):
    """Marker proving a call reached the transport instead of failing validation."""


class RefusingTransport(httpx.BaseTransport):
    """A transport that refuses to send, so "it got this far" is observable."""

    def handle_request(self, request: httpx.Request) -> httpx.Response:
        raise ReachedTransportError("the request reached the transport")


def reached_transport(error: BaseException) -> bool:
    return isinstance(error, PactmanNetworkError) and isinstance(
        error.__cause__, ReachedTransportError
    )


def is_free_tier_restriction(error: BaseException) -> bool:
    """
    True when a 404 came from the free-tier EIN allowlist rather than from an
    absent record.

    A free key carries a fixed set of accessible EINs. The server requires every
    EIN in a bulk body to be on that list and answers 404 for the whole batch
    otherwise, before any lookup runs — so partial success cannot be reached with
    such a key. That is a property of the key, not of the deployment, and the
    checks it makes unreachable are skipped rather than failed.
    """
    if not isinstance(error, PactmanNotFoundError):
        return False

    return any(
        re.search(r"accessible nonprofits", str(detail.get("reason", "")), re.IGNORECASE)
        for detail in error.api_errors
    )


# --- small helpers -----------------------------------------------------------


def record_of(nonprofit: Nonprofit | None) -> dict[str, Any]:
    """The record as the plain dict it is at runtime, for lookups by name."""
    return cast("dict[str, Any]", nonprofit or {})


def returned(record: Mapping[str, Any], field_name: str) -> bool:
    """True when the API returned the field at all, ``None`` included."""
    return field_name in record


def presence(record: Mapping[str, Any], field_name: str) -> str:
    """``present`` | ``null`` | ``absent`` — the three outcomes ex-05 turns on."""
    if field_name not in record:
        return "absent"

    return "null" if record[field_name] is None else "present"


_DATE_FORMATS = (
    "%m/%d/%Y %I:%M:%S %p",
    "%m/%d/%Y, %I:%M:%S %p",
    "%m/%d/%Y",
    "%Y-%m-%d %H:%M:%S",
    "%Y-%m-%d",
)


def parse_api_date(value: Any) -> datetime | None:
    if not isinstance(value, str) or value.strip() == "":
        return None

    text = value.strip().replace("\u202f", " ").replace("\u00a0", " ")

    for pattern in _DATE_FORMATS:
        try:
            return datetime.strptime(text, pattern)
        except ValueError:
            continue

    try:
        parsed = datetime.fromisoformat(text.replace("Z", "+00:00"))
    except ValueError:
        return None

    if parsed.tzinfo is None:
        return parsed

    return parsed.astimezone().replace(tzinfo=None)


def age_in_days(moment: datetime, now: datetime | None = None) -> int:
    return round(((now or datetime.now()) - moment).total_seconds() / 86_400)


def truncate(value: Any, length: int = 60) -> str:
    text = str(value)

    return text if len(text) <= length else f"{text[: length - 1]}…"


def as_number(value: Any) -> float | None:
    """Numbers only — ``True`` is an ``int`` in Python and must not slip through."""
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return None

    return float(value)


def envelope_of(result: Any) -> dict[str, Any]:
    """The parsed envelope, or an empty one when the body was not JSON."""
    return result.raw if isinstance(result.raw, dict) else {}


# --- check builders ----------------------------------------------------------


def from_record(
    covers: tuple[str, ...],
    name: str,
    body: Callable[[dict[str, Any], Runner], Outcome],
) -> Check:
    """
    A zero-cost check over the record the single check already fetched.

    This is what keeps coverage affordable: most of what the examples claim is a
    claim about a response, and one response answers all of them.
    """

    def run(runner: Runner) -> Outcome:
        nonprofit = runner.single_result.nonprofit if runner.single_result else None

        if not nonprofit:
            return Outcome(status="skip", detail="the single check returned no record")

        return body(record_of(nonprofit), runner)

    return Check(covers=covers, name=name, cost=0, body=run)


def source_projection(
    *,
    covers: tuple[str, ...],
    name: str,
    get: Callable[[Nonprofit], Any],
    mapping: dict[str, str],
    describe: Callable[[dict[str, Any]], str],
    absent_status: str = "warn",
) -> Check:
    """
    Checks that a grouped source view is a projection and nothing more: every key
    copied 1:1 from the field the API returned, nothing invented, and ``None``
    returned only when the source is genuinely absent.
    """

    def body(record: dict[str, Any], runner: Runner) -> Outcome:
        projected = cast("dict[str, Any] | None", get(cast("Nonprofit", record)))
        wire_fields = [field_name for field_name in mapping.values() if field_name in record]

        if projected is None:
            check_that(
                not wire_fields,
                "the projection was None while the API returned "
                f"{len(wire_fields)} of its fields",
            )
            runner.note(
                name, "the API returned nothing for this source — an absence, not a negative"
            )

            return Outcome(status=absent_status, detail="not returned for this record")

        for target, wire_field in mapping.items():
            on_wire = wire_field in record

            check_that(
                on_wire == (target in projected),
                f'"{target}" and the wire field "{wire_field}" disagree about presence',
            )

            if on_wire:
                value, source = projected[target], record[wire_field]
                check_that(
                    value is source or value == source,
                    f'"{target}" is not the value the API returned in "{wire_field}"',
                )

        invented = [key for key in projected if key not in mapping]

        check_that(
            not invented,
            f"the projection added fields the API did not send: {', '.join(invented)}",
        )

        return Outcome(
            detail=(
                f"{len(wire_fields)}/{len(mapping)} fields returned · {describe(projected)}"
            ),
            data=projected,
        )

    return from_record(covers, name, body)


# --- checks: the client itself (ex-01) ---------------------------------------


def kind_of(value: object) -> str:
    """What an exported name is, in the words the expectation table uses."""
    if isinstance(value, type):
        try:
            return "enum" if issubclass(value, Enum) else "class"
        except TypeError:
            return "class"

    if isinstance(value, Enum):
        return "enum-member"

    if callable(value):
        return "function"

    if isinstance(value, bool):
        return "bool"

    if isinstance(value, float):
        return "float"

    if isinstance(value, int):
        return "int"

    if isinstance(value, str):
        return "str"

    return type(value).__name__


def client_checks(api_key: str) -> list[Check]:
    def configuration_and_redaction(runner: Runner) -> Outcome:
        client = runner.client

        check_that(isinstance(client.base_url, str), "client.base_url is not a string")
        check_that(
            client.timeout > 0 and math.isfinite(client.timeout), "timeout is not finite"
        )

        # The credential must not be reachable from any diagnostic surface.
        surfaces = [
            repr(client),
            str(client),
            repr(vars(client)),
            json.dumps(client.to_dict(), default=str),
        ]

        for surface in surfaces:
            check_that(api_key not in surface, "the API key appeared in a diagnostic surface")

        check_that(
            client.to_dict()["api_key"] == "[redacted]",
            "to_dict did not replace the key with a placeholder",
        )

        return Outcome(
            detail=f"{client.base_url} · timeout {client.timeout}s · SDK {VERSION}"
        )

    def configuration_is_validated(runner: Runner) -> Outcome:
        rejected: list[tuple[str, Callable[[], object]]] = [
            ("no API key", lambda: PactmanClient()),
            ("a blank key", lambda: PactmanClient(api_key="   ")),
            ("a non-string key", lambda: PactmanClient(api_key=cast("Any", 1234))),
            (
                "a malformed base URL",
                lambda: PactmanClient(api_key=api_key, base_url="not a url"),
            ),
            (
                "a non-HTTP base URL",
                lambda: PactmanClient(api_key=api_key, base_url="ftp://example.org"),
            ),
            ("a zero timeout", lambda: PactmanClient(api_key=api_key, timeout=0)),
            ("an infinite timeout", lambda: PactmanClient(api_key=api_key, timeout=math.inf)),
            ("a negative retry count", lambda: RetryOptions(max_retries=-1)),
            (
                "an unknown environment",
                lambda: PactmanClient(api_key=api_key, environment="staging"),
            ),
        ]

        for description, construct in rejected:
            try:
                construct()
            except PactmanConfigurationError:
                continue
            except Exception as error:
                raise CheckFailedError(
                    f"{description}: expected PactmanConfigurationError, "
                    f"got {type(error).__name__}"
                ) from error

            raise CheckFailedError(f"{description} was accepted")

        # Defaults, which no example spells out because every example relies on them.
        with PactmanClient(api_key=api_key) as defaults:
            check_that(
                defaults.timeout == DEFAULT_TIMEOUT,
                "the default timeout is not DEFAULT_TIMEOUT",
            )
            check_that(
                defaults.base_url == base_url_for_environment(DEFAULT_ENVIRONMENT),
                "the default base URL is not the default environment",
            )
            check_that(
                defaults.environment == DEFAULT_ENVIRONMENT,
                "the default environment was not reported",
            )

        with PactmanClient(api_key=api_key, base_url="https://example.org") as explicit:
            check_that(
                explicit.environment is None,
                "an explicit base_url should report no named environment",
            )

        environments = ", ".join(str(name) for name in supported_environments())

        return Outcome(
            detail=(
                f"{len(rejected)} unusable configurations rejected locally · "
                f"defaults: {DEFAULT_TIMEOUT}s, {environments}"
            )
        )

    def exported_surface(runner: Runner) -> Outcome:
        expected = {
            "PactmanClient": "class",
            "AsyncPactmanClient": "class",
            "NonprofitsResource": "class",
            "AsyncNonprofitsResource": "class",
            "RetryOptions": "class",
            "PactmanError": "class",
            "PactmanApiError": "class",
            "PactmanAuthenticationError": "class",
            "PactmanAuthorizationError": "class",
            "PactmanBadRequestError": "class",
            "PactmanConfigurationError": "class",
            "PactmanNetworkError": "class",
            "PactmanNotFoundError": "class",
            "PactmanRateLimitError": "class",
            "PactmanServerError": "class",
            "PactmanTimeoutError": "class",
            "PactmanValidationError": "class",
            "is_pactman_error": "function",
            "normalize_ein": "function",
            "normalize_eins": "function",
            "is_valid_ein": "function",
            "base_url_for_environment": "function",
            "supported_environments": "function",
            "get_pub78": "function",
            "get_bmf": "function",
            "get_aroe": "function",
            "get_ofac": "function",
            "VERSION": "str",
            "SINGLE_CHECK_PATH": "str",
            "BULK_CHECK_PATH": "str",
            "DEFAULT_ENVIRONMENT": "enum-member",
            "DEFAULT_TIMEOUT": "float",
            "EIN_LENGTH": "int",
            "MAX_BULK_EINS": "int",
            "PactmanEnvironment": "enum",
            "PactmanErrorCategory": "enum",
            "PactmanErrorOrigin": "enum",
        }

        wrong = [
            f"{name} (expected {kind}, got {kind_of(getattr(sdk, name, None))})"
            for name, kind in expected.items()
            if kind_of(getattr(sdk, name, None)) != kind
        ]

        check_that(not wrong, f"missing or mistyped exports: {', '.join(wrong)}")

        # The server's limits belong to the server; ex-20 asks callers to import
        # them rather than copy the numbers into their own constants.
        check_that(
            isinstance(MAX_BULK_EINS, int) and MAX_BULK_EINS > 0,
            "MAX_BULK_EINS is not a positive integer",
        )
        check_that(EIN_LENGTH == 9, f"EIN_LENGTH is {EIN_LENGTH}")
        check_that(
            re.match(r"^\d+\.\d+\.\d+", VERSION) is not None,
            f'VERSION "{VERSION}" is not semver-shaped',
        )
        check_that(
            "{ein}" in SINGLE_CHECK_PATH, "SINGLE_CHECK_PATH has no {ein} placeholder"
        )
        check_that(
            sorted(sdk.__all__) == sorted(set(sdk.__all__)), "__all__ repeats a name"
        )

        return Outcome(
            detail=(
                f"{len(expected)} documented exports present of {len(sdk.__all__)} in "
                f"__all__ · MAX_BULK_EINS {MAX_BULK_EINS}"
            )
        )

    def error_taxonomy(runner: Runner) -> Outcome:
        init = PactmanApiErrorInit(status=0)
        api_cases: list[tuple[PactmanError, PactmanErrorCategory]] = [
            (PactmanBadRequestError("x", init), PactmanErrorCategory.BAD_REQUEST),
            (PactmanAuthenticationError("x", init), PactmanErrorCategory.AUTHENTICATION),
            (PactmanAuthorizationError("x", init), PactmanErrorCategory.AUTHORIZATION),
            (PactmanNotFoundError("x", init), PactmanErrorCategory.NOT_FOUND),
            (PactmanRateLimitError("x", init), PactmanErrorCategory.RATE_LIMIT),
            (PactmanServerError("x", init), PactmanErrorCategory.SERVER),
        ]
        local_cases: list[tuple[PactmanError, PactmanErrorCategory]] = [
            (PactmanValidationError("x"), PactmanErrorCategory.VALIDATION),
            (PactmanConfigurationError("x"), PactmanErrorCategory.CONFIGURATION),
            (PactmanTimeoutError("x", 1.0), PactmanErrorCategory.TIMEOUT),
            (PactmanNetworkError("x"), PactmanErrorCategory.NETWORK),
        ]

        for error, category in [*api_cases, *local_cases]:
            origin = (
                PactmanErrorOrigin.API
                if (error, category) in api_cases
                else PactmanErrorOrigin.LOCAL
            )

            check_that(
                isinstance(error, PactmanError), f"{type(error).__name__} is not a PactmanError"
            )
            check_that(
                error.category == category,
                f'{type(error).__name__} has category "{error.category}"',
            )
            check_that(
                error.origin == origin, f'{type(error).__name__} has origin "{error.origin}"'
            )
            check_that(
                is_pactman_error(error), f"is_pactman_error rejected {type(error).__name__}"
            )
            check_that(
                error.to_dict()["name"] == type(error).__name__,
                f'{type(error).__name__} reports name "{error.to_dict()["name"]}"',
            )

        # Every API error is catchable as one class; the specific ones stay specific.
        for error, _ in api_cases:
            check_that(
                isinstance(error, PactmanApiError),
                f"{type(error).__name__} is not a PactmanApiError",
            )

        check_that(
            not is_pactman_error(Exception("x")), "is_pactman_error accepted a plain Exception"
        )
        check_that(
            PactmanErrorOrigin.LOCAL.value == "local"
            and PactmanErrorOrigin.API.value == "api",
            "the origin constants are not the documented strings",
        )

        return Outcome(
            detail=(
                f"{len(api_cases) + len(local_cases)} error classes · "
                "category and origin as documented"
            )
        )

    def no_derived_verdicts(runner: Runner) -> Outcome:
        # The SDK reports what the sources said and stops. Every example says so in
        # prose; this is the executable version.
        forbidden = [
            "names_match",
            "addresses_match",
            "is_exempt",
            "is_eligible",
            "is_grant_eligible",
            "is_deductible",
            "is_revoked",
            "is_reinstated",
            "is_sanctioned",
            "is_stale",
            "has_ofac_match",
            "has_conflict",
            "score",
            "verdict",
            "decide",
            "approve",
        ]

        found = [name for name in forbidden if hasattr(sdk, name)]

        check_that(not found, f"the SDK exposes derived verdicts: {', '.join(found)}")

        return Outcome(
            detail=(
                f"none of {len(forbidden)} verdict helpers exist — policy stays in caller code"
            )
        )

    return [
        Check(("ex-01",), "configuration and redaction", 0, configuration_and_redaction),
        Check(("ex-01",), "configuration is validated", 0, configuration_is_validated),
        # The batch limit and the endpoint paths are exports ex-20 tells callers to
        # import rather than copy, so its heading names this check too.
        Check(("ex-01", "ex-20"), "exported surface", 0, exported_surface),
        # ex-22 and ex-24 name the classes their probes raise; this is the part of
        # what they claim that costs nothing and runs on every key.
        Check(
            ("ex-16", "error_handling", "ex-22", "ex-24"),
            "error taxonomy",
            0,
            error_taxonomy,
        ),
        # Every one of these examples says in prose that the helper it would have
        # been convenient to call does not exist.
        Check(
            ("ex-04", "ex-06", "ex-10", "ex-14"), "no derived verdicts", 0, no_derived_verdicts
        ),
    ]


# --- checks: local validation (ex-02, ex-15, ex-20) --------------------------


def local_validation_checks(ein: str, api_key: str) -> list[Check]:
    def malformed_input_sends_nothing(runner: Runner) -> Outcome:
        before = runner.requests_sent
        malformed: list[Any] = ["41178709", "not-an-ein", "", None, "41.1787097", 4117870971]

        for bad in malformed:
            try:
                runner.client.nonprofits.check(bad)
            except PactmanValidationError as error:
                check_that(
                    error.origin == PactmanErrorOrigin.LOCAL,
                    f'a local rejection reported origin "{error.origin}"',
                )
                continue
            except Exception as error:
                raise CheckFailedError(
                    f"expected PactmanValidationError for {bad!r}, got {type(error).__name__}"
                ) from error

            raise CheckFailedError(f"{bad!r} was accepted by local validation")

        batches: list[tuple[str, Any]] = [
            ("an empty batch", []),
            ("a bare string instead of a list", "not-a-list"),
            ("a batch with one bad entry", [ein, "nope"]),
        ]

        for description, batch in batches:
            try:
                runner.client.nonprofits.check_bulk(batch)
            except PactmanValidationError:
                continue

            raise CheckFailedError(f"{description} was accepted")

        sent = runner.requests_sent - before

        check_that(
            sent == 0,
            f"{sent} HTTP requests were sent for input that should never leave the process",
        )

        return Outcome(
            detail=(
                f"{len(malformed) + len(batches)} malformed inputs rejected in-process "
                "with 0 requests"
            )
        )

    def ein_helpers(runner: Runner) -> Outcome:
        normalized = normalize_ein(ein)

        check_that(
            re.fullmatch(r"\d{9}", normalized) is not None,
            f'normalize_ein produced "{normalized}"',
        )
        check_that(
            normalize_ein(f"  {normalized[:2]}-{normalized[2:]}  ") == normalized,
            "the hyphenated and padded form did not normalize to the plain one",
        )
        check_that(
            is_valid_ein(normalized) and is_valid_ein(f"{normalized[:2]}-{normalized[2:]}"),
            "is_valid_ein rejected a well-formed EIN",
        )
        check_that(
            not is_valid_ein("12345678")
            and not is_valid_ein(None)
            and not is_valid_ein(123456789),
            "is_valid_ein accepted a malformed value",
        )

        # Order and duplicates survive normalization; ex-18 depends on it.
        supplied = ["41-1787097", "996589560", "41-1787097"]

        check_that(
            normalize_eins(supplied) == ["411787097", "996589560", "411787097"],
            "normalize_eins reordered or deduplicated its input",
        )

        # Every failure is reported at once, by index, rather than the first one.
        try:
            normalize_eins(["41-1787097", "nope", "", "996589560"])
        except PactmanValidationError as error:
            check_that(
                len(error.issues) == 2, f"expected 2 issues, got {len(error.issues)}"
            )
            check_that(
                [issue.index for issue in error.issues] == [1, 2],
                "the issues did not identify the failing positions",
            )
        else:
            raise CheckFailedError("normalize_eins accepted two malformed entries")

        return Outcome(
            detail=(
                f"{EIN_LENGTH}-digit normalization · order and duplicates preserved · "
                "issues by index"
            )
        )

    def bulk_batch_limit_is_local(runner: Runner) -> Outcome:
        at_limit = [str(100000000 + index) for index in range(MAX_BULK_EINS)]
        over_limit = [*at_limit, "100000999"]
        # `dedupe` collapses before the limit applies, so a duplicate-heavy list
        # that exceeds the limit as supplied still goes out.
        duplicate_heavy = [str(100000000 + index % 10) for index in range(MAX_BULK_EINS + 10)]
        before = runner.requests_sent

        # A transport that refuses to send. Reaching it proves local validation
        # passed; never reaching it proves the batch was rejected in-process.
        with httpx.Client(transport=RefusingTransport()) as http_client:
            probe = PactmanClient(
                api_key=api_key,
                base_url=runner.client.base_url,
                retry=False,
                http_client=http_client,
            )

            reached = False

            try:
                probe.nonprofits.check_bulk(at_limit)
            except Exception as error:
                reached = reached_transport(error)

            check_that(reached, f"a batch of exactly {MAX_BULK_EINS} was rejected locally")

            try:
                probe.nonprofits.check_bulk(over_limit)
            except PactmanValidationError as error:
                check_that(
                    str(MAX_BULK_EINS) in str(error),
                    "the rejection did not name the limit that was exceeded",
                )
            except Exception as error:
                raise CheckFailedError(
                    f"an over-limit batch raised {type(error).__name__}"
                ) from error
            else:
                raise CheckFailedError(f"a batch of {len(over_limit)} was accepted")

            deduped_reached = False

            try:
                probe.nonprofits.check_bulk(duplicate_heavy, dedupe=True)
            except Exception as error:
                deduped_reached = reached_transport(error)

        check_that(
            deduped_reached, "dedupe did not collapse duplicates before the limit was applied"
        )
        check_that(
            runner.requests_sent == before,
            "the over-limit batch was sent through the real transport",
        )

        return Outcome(
            detail=(
                f"{MAX_BULK_EINS} accepted · {len(over_limit)} rejected in-process · "
                "dedupe collapses first"
            )
        )

    return [
        Check(
            ("ex-15", "error_handling"),
            "malformed input sends nothing",
            0,
            malformed_input_sends_nothing,
        ),
        Check(("ex-02", "ex-15", "ex-18"), "EIN helpers", 0, ein_helpers),
        Check(("ex-20", "bulk"), "bulk batch limit is local", 0, bulk_batch_limit_is_local),
    ]


# --- checks: authentication (ex-01, ex-23) -----------------------------------


def authentication_checks(ein: str, base_url: str) -> list[Check]:
    def authentication_is_enforced(runner: Runner) -> Outcome:
        with httpx.Client(transport=CountingTransport()) as http_client:
            client = PactmanClient(
                api_key=INVALID_API_KEY,
                base_url=base_url,
                retry=False,
                timeout=15.0,
                http_client=http_client,
            )

            try:
                client.nonprofits.check(ein)
            except PactmanAuthenticationError as error:
                check_that(
                    error.origin == PactmanErrorOrigin.API,
                    f'expected origin "api", got {error.origin}',
                )
                check_that(
                    INVALID_API_KEY not in json.dumps(error.to_dict(), default=str),
                    "the rejected key appeared in error diagnostics",
                )

                return Outcome(detail=f"HTTP {error.status} → PactmanAuthenticationError")
            except PactmanApiError as error:
                runner.note(
                    "authentication is enforced",
                    f"an invalid key produced HTTP {error.status} "
                    f"({type(error).__name__}), not 401",
                )

                return Outcome(
                    status="warn",
                    detail=f"rejected, but as HTTP {error.status} rather than 401",
                )

        return Outcome(
            status="fail",
            detail="an invalid key was accepted — check what INVALID_API_KEY was set to",
        )

    def rejected_keys_are_not_retried(runner: Runner) -> Outcome:
        # Retrying a rejected key just burns the same key three times. The policy
        # says 401/403/404 are never retried whatever `retryable_statuses` holds;
        # this is the live proof, counted at the socket.
        counter = CountingTransport()
        status: int | None = None

        with httpx.Client(transport=counter) as http_client:
            client = PactmanClient(
                api_key=INVALID_API_KEY,
                base_url=base_url,
                retry=RetryOptions(
                    max_retries=2,
                    initial_delay=0.01,
                    retryable_statuses=(401, 403, 404, 429, 500),
                ),
                timeout=15.0,
                http_client=http_client,
            )

            try:
                client.nonprofits.check(ein)
            except PactmanApiError as error:
                status = error.status
                check_that(
                    error.attempts == 1, f"the error reports {error.attempts} attempts"
                )
            except PactmanError:
                status = None

        if status is not None and status not in (401, 403, 404):
            runner.note(
                "rejected keys are not retried",
                f"the invalid key produced HTTP {status}, which is retryable — "
                "the no-retry rule was not exercised",
            )

            return Outcome(
                status="warn", detail=f"HTTP {status} after {counter.sent} request(s)"
            )

        check_that(
            counter.sent == 1,
            f"a rejected key was sent {counter.sent} times with retries on and 401 "
            "in retryable_statuses",
        )

        return Outcome(
            detail=(
                f"HTTP {status if status is not None else 'none'} · 1 request, no retry, "
                "even when listed as retryable"
            )
        )

    return [
        Check(
            ("ex-01", "error_handling"),
            "authentication is enforced",
            0,
            authentication_is_enforced,
        ),
        Check(("ex-23",), "rejected keys are not retried", 0, rejected_keys_are_not_retried),
    ]


# --- checks: the single check and its record (ex-02..ex-05, ex-16) -----------


def single_check_checks(ein: str, api_key: str) -> list[Check]:
    def single_check(runner: Runner) -> Outcome:
        sent_at = time.monotonic()
        result = runner.client.nonprofits.check(ein)

        # Recorded so the timeout probe can pick a deadline that is shorter than a
        # real round trip but longer than connection setup.
        runner.observed_round_trip = time.monotonic() - sent_at
        runner.observe_cycle_count(result.check_count)

        check_that(result.status == 200, f"expected HTTP 200, got {result.status}")
        check_that(
            result.nonprofit is not None,
            f"no record returned for {ein} — EIN needs one that exists",
        )

        record = record_of(result.nonprofit)

        check_that(
            record.get("ein") == normalize_ein(ein),
            f"response EIN {record.get('ein')} does not match the normalized request "
            f"{normalize_ein(ein)}",
        )

        runner.single_result = result

        return Outcome(
            detail=(
                f"{record.get('organization_name')} · "
                f"request {result.request_id or 'no id'}"
            ),
            data={"check_count": result.check_count, "time_taken_ms": result.time_taken_ms},
        )

    def envelope_shape(runner: Runner) -> Outcome:
        result = runner.single_result

        if not result:
            return Outcome(status="skip", detail="the single check did not return a record")

        envelope = envelope_of(result)
        envelope_keys = list(envelope)

        for key in ("code", "message", "data"):
            check_that(key in envelope_keys, f'the envelope is missing "{key}"')

        check_that(
            isinstance(envelope["code"], int),
            f'envelope "code" is {type(envelope["code"]).__name__}',
        )
        check_that(
            isinstance(result.errors, list), "result.errors was not normalized to a list"
        )
        check_that(
            result.check_count is None or isinstance(result.check_count, int),
            "check_count is neither a number nor None",
        )
        check_that(
            result.time_taken_ms is None or isinstance(result.time_taken_ms, (int, float)),
            "time_taken_ms is neither a number nor None",
        )
        check_that(
            result.request_id is None or isinstance(result.request_id, str),
            "request_id is neither a string nor None",
        )

        missing = [
            key for key in ("timeTaken", "nonprofit_check_count") if key not in envelope_keys
        ]

        if missing:
            runner.note("envelope shape", f"envelope did not include: {', '.join(missing)}")

        # A numeric field that arrives as something else reads as `None`, which
        # looks exactly like "not reported" downstream. Say so rather than let the
        # usage checks skip themselves for a reason nobody sees.
        mistyped = [
            (key, wire)
            for key, wire, parsed in (
                (
                    "nonprofit_check_count",
                    envelope.get("nonprofit_check_count"),
                    result.check_count,
                ),
                ("timeTaken", envelope.get("timeTaken"), result.time_taken_ms),
            )
            if wire is not None and parsed is None
        ]

        for key, wire in mistyped:
            runner.note(
                "envelope shape",
                f'"{key}" arrived as {type(wire).__name__} ({wire!r}), not a number — '
                "it is reported as None",
            )

        if result.request_id is None:
            runner.note(
                "envelope shape",
                "no correlation header was returned — audit trails lose the request id",
            )

        return Outcome(
            status="warn" if missing or mistyped else "pass",
            detail=(
                f"{len(envelope_keys)} envelope keys · code {envelope['code']} · "
                f"{result.time_taken_ms if result.time_taken_ms is not None else '?'}ms "
                "server-side"
                + (f" · {len(mistyped)} numeric field(s) mistyped" if mistyped else "")
            ),
            data={"envelope_keys": envelope_keys},
        )

    def model_field_coverage(record: dict[str, Any], runner: Runner) -> Outcome:
        # Drift detection. New fields are expected over time and are not failures;
        # they are the reason the record is a plain dict.
        unknown = [key for key in record if key not in KNOWN_NONPROFIT_FIELDS]
        absent = [key for key in KNOWN_NONPROFIT_FIELDS if key not in record]

        if unknown:
            runner.note(
                "model field coverage",
                f"fields newer than this SDK: {', '.join(unknown)} — readable through the "
                "record's own dict",
            )

        if absent:
            runner.note(
                "model field coverage",
                f"documented fields not returned for this record: {', '.join(sorted(absent))}",
            )

        return Outcome(
            detail=(
                f"{len(record)} fields · {len(unknown)} newer than the SDK · "
                f"{len(absent)} not returned"
            ),
            data={"unknown": unknown, "absent": sorted(absent)},
        )

    def identity_fields(record: dict[str, Any], runner: Runner) -> Outcome:
        check_that(
            re.fullmatch(r"\d{9}", str(record.get("ein"))) is not None,
            f'ein came back as "{record.get("ein")}"',
        )
        check_that(
            isinstance(record.get("organization_name"), str)
            and str(record.get("organization_name")).strip() != "",
            "organization_name is missing or empty",
        )

        url = record.get("pactman_org_url")

        if isinstance(url, str) and not re.match(r"^https?://\S+$", url):
            runner.note("identity fields", f"pactman_org_url is not a URL: {url}")

        modified = parse_api_date(record.get("organization_info_last_modified"))

        return Outcome(
            detail=(
                f"{record.get('ein')} · {truncate(record.get('organization_name'), 40)}"
                + ("" if modified is None else f" · modified {age_in_days(modified)}d ago")
            )
        )

    def name_fields(record: dict[str, Any], runner: Runner) -> Outcome:
        names = {
            key: record.get(key)
            for key in (
                "organization_name",
                "organization_name_aka",
                "pub78_organization_name",
                "bmf_organization_name",
            )
        }

        for field_name, value in names.items():
            check_that(
                value is None or isinstance(value, str),
                f"{field_name} came back as {type(value).__name__}",
            )

        # Each source keeps its own spelling. Differences between them are normal,
        # and reconciling them is the caller's policy (ex-04).
        spellings = {
            value for value in names.values() if isinstance(value, str) and value.strip() != ""
        }

        if len(spellings) > 1:
            joined = " vs ".join(f'"{name}"' for name in sorted(spellings))
            runner.note("name fields", f"the sources spell the name differently: {joined}")

        return Outcome(
            detail=(
                f"{len(spellings)} distinct spelling(s) preserved across "
                f"{len(names)} name fields"
            ),
            data=names,
        )

    def address_fields(record: dict[str, Any], runner: Runner) -> Outcome:
        fields = ["address_line1", "address_line2", "city", "state", "state_name", "zip"]
        states = {name: presence(record, name) for name in fields}

        # "Returned as null" and "not returned" are different answers, and the SDK
        # must not flatten one into the other (ex-05).
        unconfirmed = [name for name in fields if states[name] != "present"]

        if unconfirmed:
            runner.note(
                "address fields",
                f"no value returned for {', '.join(unconfirmed)} — these components are "
                "unconfirmed, not mismatched",
            )

        return Outcome(
            detail=(
                f"{len(fields) - len(unconfirmed)}/{len(fields)} components returned "
                "with a value"
            ),
            data=states,
        )

    def normalization_end_to_end(runner: Runner) -> Outcome:
        normalized = normalize_ein(ein)
        hyphenated = f"  {normalized[:2]}-{normalized[2:]}  "
        before = len(runner.requests)
        result = runner.client.nonprofits.check(hyphenated)

        runner.observe_cycle_count(result.check_count)

        check_that(result.nonprofit is not None, "the hyphenated form returned no record")

        record = record_of(result.nonprofit)

        check_that(
            record.get("ein") == normalized,
            f"hyphenated input resolved to {record.get('ein')}, expected {normalized}",
        )

        # The hyphen and the whitespace are normalized before the URL is built.
        sent = runner.requests[before:]
        url = sent[-1].url if sent else ""

        check_that(
            url.endswith(f"/{normalized}"),
            f"the request URL did not carry the normalized EIN: {url}",
        )
        check_that(hyphenated.strip() not in url, "the hyphenated form reached the URL")

        return Outcome(
            detail=f'"{hyphenated.strip()}" and "{normalized}" address the same record'
        )

    def not_found(runner: Runner) -> Outcome:
        before = runner.requests_sent

        try:
            result = runner.client.nonprofits.check(MISSING_EIN)
        except PactmanNotFoundError as error:
            check_that(error.status == 404, f"expected status 404, got {error.status}")
            check_that(
                error.origin == PactmanErrorOrigin.API,
                f'expected origin "api", got {error.origin}',
            )
            check_that(
                isinstance(error, PactmanApiError),
                "PactmanNotFoundError is not catchable as PactmanApiError",
            )

            # A 404 cannot become a record by asking again (ex-23).
            attempts = runner.requests_sent - before

            check_that(attempts == 1, f"a 404 was retried: {attempts} requests")

            # Diagnostics must be safe to log verbatim.
            check_that(
                api_key not in json.dumps(error.to_dict(), default=str),
                "the API key appeared in error diagnostics",
            )

            return Outcome(
                detail=(
                    f"HTTP 404 → PactmanNotFoundError · apiCode {error.api_code} · "
                    f"{len(error.api_errors)} detail(s) · not retried"
                )
            )
        except PactmanApiError as error:
            runner.note("not found", f"a missing EIN produced HTTP {error.status}, not 404")

            return Outcome(
                status="warn", detail=f"HTTP {error.status} ({type(error).__name__})"
            )

        runner.observe_cycle_count(result.check_count)

        if result.nonprofit:
            return Outcome(
                status="warn",
                detail=(
                    f"{MISSING_EIN} unexpectedly has a record — MISSING_EIN needs "
                    "an unused one"
                ),
            )

        runner.note("not found", "a missing EIN returned HTTP 200 with no record, not 404")

        return Outcome(status="warn", detail=f"HTTP {result.status} with data: null, not a 404")

    return [
        # The one fetch every record-derived check below reads.
        Check(("ex-03", "quickstart", "ex-26", "ex-27"), "single check", 1, single_check),
        Check(("ex-03", "ex-21"), "envelope shape", 0, envelope_shape),
        from_record(("ex-25", "ex-03"), "model field coverage", model_field_coverage),
        from_record(("ex-03",), "identity fields", identity_fields),
        from_record(("ex-04",), "name fields", name_fields),
        from_record(("ex-05",), "address fields", address_fields),
        Check(("ex-02",), "EIN normalization end to end", 1, normalization_end_to_end),
        Check(("ex-16",), "not found", 1, not_found),
    ]


# --- checks: the sources (ex-06..ex-14) --------------------------------------


def source_checks() -> list[Check]:
    def describe_pub78(pub78: dict[str, Any]) -> str:
        types = pub78.get("organization_types") or []
        limitation = types[0].get("deductibility_limitation") if types else None

        return (
            f"verified: {pub78.get('verified', 'not reported')} · "
            f"{len(types)} deductibility entr{'y' if len(types) == 1 else 'ies'}"
            + (f" · {truncate(limitation, 24)}" if limitation else "")
        )

    def describe_bmf(bmf: dict[str, Any]) -> str:
        return (
            f"status: {bmf.get('status', 'not reported')} · "
            f"subsection {bmf.get('subsection') or '—'} · "
            f"{truncate(bmf.get('subsection_description') or 'no description', 30)}"
        )

    def describe_aroe(aroe: dict[str, Any]) -> str:
        if not aroe.get("revocation_date") and not aroe.get("revocation_code"):
            return "no revocation on this record"

        revoked = parse_api_date(aroe.get("revocation_date"))
        reinstated = parse_api_date(aroe.get("reinstatement_date"))
        gap = (
            f" · {(reinstated - revoked).days}d gap"
            if revoked is not None and reinstated is not None
            else ""
        )

        return (
            f"revoked {aroe.get('revocation_date') or '?'} "
            f"({aroe.get('revocation_code') or 'no code'}){gap}"
        )

    def describe_ofac(ofac: dict[str, Any]) -> str:
        # The API reports a sentence. If it ever becomes a boolean, a caller who
        # was told to read prose needs to hear about it.
        status = ofac.get("status")

        shown = truncate("None" if status is None else status, 44)

        return f'"{shown}" ({type(status).__name__})'

    def ofac_stays_four_valued(record: dict[str, Any], runner: Runner) -> Outcome:
        ofac = cast("dict[str, Any] | None", get_ofac(cast("Nonprofit", record)))

        if ofac is None:
            state = "unavailable"
        elif ofac.get("status") is None:
            state = "null"
        else:
            state = type(ofac["status"]).__name__

        check_that(
            state != "bool",
            "ofac_status came back as a boolean — screening logic that reads prose will "
            "silently break",
        )

        if state == "unavailable":
            runner.note(
                "OFAC stays four-valued",
                "nothing was screened against the SDN list for this record",
            )

        return Outcome(
            status="warn" if state == "unavailable" else "pass",
            detail=(
                f"screened → {'a sentence' if state == 'str' else state} · "
                "no boolean derived from it"
            ),
        )

    def cross_source_conflict(record: dict[str, Any], runner: Runner) -> Outcome:
        conflict = record.get("irs_bmf_pub78_conflict")

        check_that(
            conflict is None or isinstance(conflict, bool),
            f"irs_bmf_pub78_conflict came back as {type(conflict).__name__}",
        )

        if conflict is True:
            runner.note(
                "cross-source conflict",
                f"BMF and Publication 78 disagree: bmf_status {record.get('bmf_status')}, "
                f"pub78_verified {record.get('pub78_verified')} — both preserved, "
                "neither resolved",
            )

            return Outcome(detail="conflict reported and both sources preserved")

        return Outcome(
            detail=(
                "no conflict between BMF and Publication 78"
                if conflict is False
                else "the API did not report a conflict flag for this record"
            )
        )

    def foundation_classification(record: dict[str, Any], runner: Runner) -> Outcome:
        foundation_description = (
            record.get("foundation_code_description") or "no foundation description"
        )
        pairs = [
            ("bmf_subsection", "subsection_description"),
            ("foundation_code", "foundation_code_description"),
            ("foundation_type_code", "foundation_type_description"),
        ]

        # A description is the source's own label. One arriving without its code
        # would mean the label came from somewhere else (ex-12).
        for code, description in pairs:
            if record.get(description) is not None:
                check_that(
                    code in record,
                    f"{description} was returned without {code} — the label has no source "
                    "value behind it",
                )

        described = sum(1 for _, description in pairs if record.get(description))

        if described < len(pairs):
            runner.note(
                "foundation classification",
                f"{len(pairs) - described} classification code(s) arrived without "
                "a description",
            )

        return Outcome(
            detail=(
                f"509(a): {record.get('foundation_509a_status') or '—'} · "
                f"{truncate(foundation_description, 34)}"
            ),
            data={"described": described, "of": len(pairs)},
        )

    def filing_and_exemption_metadata(record: dict[str, Any], runner: Runner) -> Outcome:
        codes = [
            "filing_req_code",
            "exempt_status_code",
            "group_exemption",
            "bmf_source_pf_filing_req_cd",
            "ruling_month",
            "ruling_year",
        ]

        # Codes are preserved exactly as sent — never coerced, never re-labelled.
        for code in codes:
            value = record.get(code)

            check_that(
                value is None or isinstance(value, (str, int, float)),
                f"{code} came back as {type(value).__name__}",
            )

        year, month = record.get("ruling_year"), record.get("ruling_month")

        if year is not None and not 1900 <= int(str(year) or 0) <= datetime.now().year:
            runner.note("filing and exemption metadata", f'ruling_year is "{year}"')

        if month is not None and not 1 <= int(str(month) or 0) <= 12:
            runner.note("filing and exemption metadata", f'ruling_month is "{month}"')

        returned_codes = [code for code in codes if record.get(code)]

        return Outcome(
            detail=(
                f"{len(returned_codes)}/{len(codes)} codes returned verbatim · "
                f"ruling {month or '?'}/{year or '?'}"
            ),
            data={code: record.get(code) for code in codes},
        )

    def data_freshness(record: dict[str, Any], runner: Runner) -> Outcome:
        date_fields = [
            "report_date",
            "organization_info_last_modified",
            "most_recent_bmf",
            "most_recent_pub78",
            "ofac_list_published_date",
            "aroe_list_published_date",
            "revocation_date",
            "reinstatement_date",
        ]

        now = datetime.now()
        ages: list[tuple[str, int]] = []
        unparsable: list[str] = []
        future: list[str] = []

        for name in date_fields:
            value = record.get(name)

            if value is None or value == "":
                continue

            moment = parse_api_date(value)

            if moment is None:
                unparsable.append(f'{name}="{value}"')
                continue

            if moment > now + timedelta(days=1):
                future.append(f"{name}={value}")

            ages.append((name, age_in_days(moment, now)))

        if unparsable:
            runner.note(
                "data freshness", f"dates that do not parse as dates: {', '.join(unparsable)}"
            )

        if future:
            runner.note("data freshness", f"dates in the future: {', '.join(future)}")

        if not ages:
            runner.note(
                "data freshness",
                "no source date was returned — the record carries no freshness signal",
            )

            return Outcome(status="warn", detail="no dates on this record")

        oldest = max(ages, key=lambda entry: entry[1])

        return Outcome(
            status="warn" if unparsable or future else "pass",
            detail=(
                f"{len(ages)}/{len(date_fields)} dates · oldest {oldest[0]} at {oldest[1]}d"
            ),
            data={"ages": dict(ages)},
        )

    return [
        source_projection(
            covers=("ex-07",),
            name="Publication 78 projection",
            get=get_pub78,
            mapping={
                "verified": "pub78_verified",
                "organization_name": "pub78_organization_name",
                "ein": "pub78_ein",
                "city": "pub78_city",
                "state": "pub78_state",
                "indicator": "pub78_indicator",
                "church_message": "pub78_church_message",
                "source_org_type_1": "pub78_source_org_type_1",
                "source_org_type_2": "pub78_source_org_type_2",
                "source_org_type_3": "pub78_source_org_type_3",
                "organization_types": "organization_types",
                "most_recent": "most_recent_pub78",
            },
            describe=describe_pub78,
        ),
        source_projection(
            covers=("ex-06",),
            name="BMF projection",
            get=get_bmf,
            mapping={
                "status": "bmf_status",
                "organization_name": "bmf_organization_name",
                "ein": "bmf_ein",
                "city": "bmf_city",
                "state": "bmf_state",
                "street_address": "bmf_street_address",
                "church_message": "bmf_church_message",
                "subsection": "bmf_subsection",
                "subsection_description": "subsection_description",
                "foundation_code": "foundation_code",
                "foundation_code_description": "foundation_code_description",
                "foundation_type_code": "foundation_type_code",
                "foundation_type_description": "foundation_type_description",
                "foundation_509a_status": "foundation_509a_status",
                "ruling_month": "ruling_month",
                "ruling_year": "ruling_year",
                "group_exemption": "group_exemption",
                "exempt_status_code": "exempt_status_code",
                "filing_req_code": "filing_req_code",
                "pf_filing_req_cd": "bmf_source_pf_filing_req_cd",
                "deductability_text": "bmf_deductability_text",
                "most_recent": "most_recent_bmf",
            },
            describe=describe_bmf,
        ),
        source_projection(
            covers=("ex-08", "ex-09"),
            name="revocation (AROE) projection",
            get=get_aroe,
            # Most organizations were never revoked, so an absent source is the
            # ordinary case here rather than something to flag.
            absent_status="pass",
            mapping={
                "revocation_code": "revocation_code",
                "revocation_date": "revocation_date",
                "reinstatement_date": "reinstatement_date",
                "list_published_date": "aroe_list_published_date",
            },
            describe=describe_aroe,
        ),
        source_projection(
            covers=("ex-10",),
            name="OFAC projection",
            get=get_ofac,
            mapping={
                "status": "ofac_status",
                "list_published_date": "ofac_list_published_date",
            },
            describe=describe_ofac,
        ),
        from_record(("ex-10",), "OFAC stays four-valued", ofac_stays_four_valued),
        from_record(("ex-11",), "cross-source conflict", cross_source_conflict),
        from_record(("ex-12",), "foundation classification", foundation_classification),
        from_record(("ex-13",), "filing and exemption metadata", filing_and_exemption_metadata),
        from_record(("ex-14",), "data freshness", data_freshness),
    ]


# --- checks: forward compatibility (ex-25) -----------------------------------


def forward_compatibility_checks() -> list[Check]:
    def raw_envelope_is_unmodified(runner: Runner) -> Outcome:
        result = runner.single_result

        if not result:
            return Outcome(status="skip", detail="the single check did not return a record")

        envelope = envelope_of(result)
        data = envelope.get("data")
        expected = data[0] if isinstance(data, list) and data else data

        check_that(
            result.nonprofit is expected,
            "result.nonprofit is a copy of the body, not the body itself",
        )
        check_that(
            result.check_count == as_number(envelope.get("nonprofit_check_count")),
            "check_count does not match the envelope it was read from",
        )
        check_that(
            result.time_taken_ms == as_number(envelope.get("timeTaken")),
            "time_taken_ms does not match the envelope it was read from",
        )

        return Outcome(
            detail=f"raw carries {len(envelope)} envelope keys, none rewritten"
        )

    def no_wire_field_is_dropped(record: dict[str, Any], runner: Runner) -> Outcome:
        envelope = envelope_of(runner.single_result)
        data = envelope.get("data")
        first = data[0] if isinstance(data, list) and data else data
        wire: dict[str, Any] = first if isinstance(first, dict) else {}

        # Whatever the API adds, the installed SDK still hands it over.
        for name, value in wire.items():
            check_that(name in record, f'the wire field "{name}" is not readable on the record')
            check_that(
                record[name] is value or record[name] == value,
                f'the value of "{name}" was altered between the wire and the record',
            )

        unknown = [name for name in wire if name not in KNOWN_NONPROFIT_FIELDS]

        check_that(
            record.get("a_field_this_api_has_never_sent") is None,
            "reading an absent field invented a value for it",
        )

        return Outcome(
            detail=(
                f"{len(wire)} wire fields readable · "
                + (
                    f"{len(unknown)} newer than this SDK and still reachable"
                    if unknown
                    else "none newer than this SDK on this record"
                )
            ),
            data={"unknown": unknown},
        )

    return [
        Check(("ex-25",), "raw envelope is unmodified", 0, raw_envelope_is_unmodified),
        from_record(("ex-25",), "no wire field is dropped", no_wire_field_is_dropped),
    ]


# --- checks: bulk (ex-17..ex-21) ---------------------------------------------


def bulk_checks(eins: Sequence[str]) -> list[Check]:
    bulk_eins = list(eins[:3])
    duplicate_probe = [eins[1], eins[0], eins[1]] if len(eins) >= 2 else None

    def bulk_partial_success(runner: Runner) -> Outcome:
        submitted = [*bulk_eins, MISSING_EIN]

        try:
            result = runner.client.nonprofits.check_bulk(submitted)
        except PactmanNotFoundError as error:
            if not is_free_tier_restriction(error):
                raise

            # The batch was refused for containing an EIN outside the key's
            # allowlist, so nothing was looked up and partial success was never
            # exercised. Record the key class for the checks that depend on it.
            runner.free_tier_key = True
            runner.note(
                "bulk partial success",
                "this key restricts bulk requests to a fixed set of EINs, so a batch "
                f"containing {MISSING_EIN} was refused whole — rerun with a key that has "
                "open bulk access to verify partial success",
            )

            return Outcome(
                status="skip",
                detail="the key restricts bulk EINs to an allowlist — partial success is "
                "unreachable",
            )

        runner.observe_cycle_count(result.check_count)
        runner.capture_bulk(result, submitted)

        check_that(
            result.status == 200,
            f"a batch with matches and misses returned HTTP {result.status}, expected 200",
        )
        check_that(bool(result.organizations), "no organizations were returned")

        if normalize_ein(MISSING_EIN) not in result.not_found_eins:
            runner.note(
                "bulk partial success",
                "the missing EIN was not reported in errors[].eins; not_found_eins = "
                f"{result.not_found_eins}",
            )

        # Every input must map to a matched record or a reported failure.
        matched = {record_of(org).get("ein") for org in result.organizations}
        missing = set(result.not_found_eins)
        unaccounted = [
            normalize_ein(value)
            for value in submitted
            if normalize_ein(value) not in matched and normalize_ein(value) not in missing
        ]

        if unaccounted:
            runner.note(
                "bulk partial success",
                f"inputs with neither a record nor an error: {', '.join(unaccounted)}",
            )

        return Outcome(
            status="warn" if unaccounted else "pass",
            detail=(
                f"{len(result.organizations)} matched · {len(result.not_found_eins)} missing · "
                f"{len(result.errors)} error entries"
            ),
            data={"not_found_eins": result.not_found_eins},
        )

    def bulk_order_and_duplicates(runner: Runner) -> Outcome:
        assert duplicate_probe is not None
        before = len(runner.requests)
        result = runner.client.nonprofits.check_bulk(duplicate_probe)

        runner.observe_cycle_count(result.check_count)
        runner.capture_bulk(result, duplicate_probe)

        requested = [normalize_ein(value) for value in duplicate_probe]
        returned_eins = [str(record_of(org).get("ein")) for org in result.organizations]
        unique_requested = list(dict.fromkeys(requested))

        # The SDK sends what it was given, duplicates and order included.
        sent = runner.requests[before:]
        sent_body = sent[-1].body if sent else None

        if sent_body is not None:
            check_that(
                json.loads(sent_body) == requested,
                f"the request body was {sent_body}, not the EINs as supplied",
            )

        positional = returned_eins == requested
        deduped_order = returned_eins == unique_requested
        collapsed = len(returned_eins) == len(set(returned_eins))

        # These are observations about the deployment, recorded either way — the
        # README's claims are what they check.
        runner.note(
            "bulk order and duplicates",
            f"sent [{', '.join(requested)}] → received [{', '.join(returned_eins)}]",
        )
        runner.note(
            "bulk order and duplicates",
            "response order matched request order on this call — the API does not "
            "guarantee it, so keep indexing by EIN"
            if positional
            else "response order did not match request order, as documented — index by EIN",
        )

        check_that(
            collapsed,
            "a duplicated EIN was returned more than once, which contradicts set matching",
        )

        return Outcome(
            detail=(
                f"duplicate collapsed to one record · request-order match: {positional} · "
                f"deduped-order match: {deduped_order}"
            ),
            data={"requested": requested, "returned": returned_eins},
        )

    def bulk_and_single_agree(runner: Runner) -> Outcome:
        single = record_of(runner.single_result.nonprofit) if runner.single_result else {}
        bulk = runner.bulk_result

        if not single or bulk is None:
            return Outcome(status="skip", detail="both a single and a bulk result are needed")

        twin = next(
            (
                record_of(org)
                for org in bulk.organizations
                if record_of(org).get("ein") == single.get("ein")
            ),
            None,
        )

        if twin is None:
            return Outcome(
                status="skip", detail=f"{single.get('ein')} was not among the bulk results"
            )

        check_that(
            twin.get("organization_name") == single.get("organization_name"),
            "the two endpoints disagree about the name: "
            f"\"{single.get('organization_name')}\" vs \"{twin.get('organization_name')}\"",
        )

        # A record that is thinner in bulk is a real trap for anyone who screens in
        # bulk and reads fields the single endpoint taught them to expect.
        only_single = [name for name in single if name not in twin]
        only_bulk = [name for name in twin if name not in single]

        if only_single:
            runner.note(
                "bulk and single agree",
                f"the bulk record omits: {', '.join(only_single)} — do not assume bulk "
                "records are complete",
            )

        if only_bulk:
            runner.note(
                "bulk and single agree",
                f"only the bulk record carries: {', '.join(only_bulk)}",
            )

        return Outcome(
            status="warn" if only_single or only_bulk else "pass",
            detail=(
                f"identical field sets for {single.get('ein')} on both endpoints"
                if not only_single and not only_bulk
                else (
                    f"{len(only_single)} field(s) only in single · "
                    f"{len(only_bulk)} only in bulk"
                )
            ),
            data={"only_single": only_single, "only_bulk": only_bulk},
        )

    def bulk_usage_accounting(runner: Runner) -> Outcome:
        single = runner.single_result
        bulk = runner.bulk_result

        if single is None or bulk is None:
            return Outcome(status="skip", detail="both a single and a bulk result are needed")

        if single.check_count is None or bulk.check_count is None:
            return Outcome(
                status="skip", detail="the API did not report nonprofit_check_count"
            )

        check_that(
            bulk.check_count >= single.check_count,
            f"the counter fell from {single.check_count} to {bulk.check_count} between a "
            "single and a bulk call",
        )

        batch_size = len(runner.bulk_submitted)

        # If it ever equals the batch size, someone is about to reconstruct usage
        # from their own input and be wrong (ex-18, ex-21).
        if bulk.check_count == batch_size:
            runner.note(
                "bulk usage accounting",
                f"the bulk response reported {bulk.check_count}, exactly the batch size — "
                "verify it is still a cycle total",
            )

            return Outcome(
                status="warn",
                detail=f"check_count {bulk.check_count} equals the {batch_size}-EIN batch size",
            )

        return Outcome(
            detail=(
                f"{single.check_count} → {bulk.check_count} across a {batch_size}-EIN batch · "
                "a cycle total, not a batch size"
            ),
            data={"single": single.check_count, "bulk": bulk.check_count},
        )

    checks = [
        Check(
            ("ex-19", "bulk"), "bulk partial success", len(bulk_eins) + 1, bulk_partial_success
        )
    ]

    if duplicate_probe is not None:
        checks.append(
            Check(
                ("ex-18",),
                "bulk order and duplicates",
                len(duplicate_probe),
                bulk_order_and_duplicates,
            )
        )

    checks.append(Check(("ex-17",), "bulk and single agree", 0, bulk_and_single_agree))
    checks.append(Check(("ex-21",), "bulk usage accounting", 0, bulk_usage_accounting))

    return checks


# --- checks: the raw response contract ---------------------------------------


def contract_checks() -> list[Check]:
    """
    Four checks that hold the raw JSON this run received against a recorded
    baseline: the schema and the types of the single-check response, and the same
    two for bulk.

    Everything else in this file asserts what the SDK does with a response. These
    assert that the response itself has not moved — a field the API stopped
    sending, one it started sending, one that changed from a boolean to a string
    or from ``M/D/YYYY h:mm:ss AM`` to ISO. None of it is knowable from the SDK's
    own types, which are permissive by design so a server-side change cannot break
    deserialization; this is where such a change is meant to become visible.

    Free. Both responses were already fetched and paid for by the checks above.

    The first run against a deployment has nothing to compare to, so it records
    what it saw and says so; every run after that is a comparison. A fifth entry
    writes the file when there is something new to write, and stands down when
    there is not. Deleting the file is how a recording is redone, and deleting it
    is deliberate work — re-recording discards the evidence a comparison gives.

    The baseline holds shapes only — path, type and value format, never a value —
    so it is safe to commit and a failure is safe to print. See ``contract.py``.
    """
    baseline_path = Path(__file__).resolve().parent / "contract-baseline.json"
    state: dict[str, Any] = {"baseline": None, "loaded": False}
    observed: dict[str, dict[str, Any]] = {}
    pending: set[str] = set()
    announced_target = [False]

    def load_baseline() -> dict[str, Any]:
        if not state["loaded"]:
            state["loaded"] = True
            state["baseline"] = (
                json.loads(baseline_path.read_text(encoding="utf-8"))
                if baseline_path.exists()
                else None
            )

        return cast("dict[str, Any]", state["baseline"] or {})

    def observe(runner: Runner, kind: str) -> dict[str, Any]:
        """Signatures this run observed, by endpoint. Built once, read by both checks."""
        if kind not in observed:
            if kind == "single":
                raw = runner.single_result.raw if runner.single_result else None
                subject: dict[str, Any] = {
                    "ein": record_of(
                        runner.single_result.nonprofit if runner.single_result else None
                    ).get("ein")
                }
                absent = "the single check did not return a response"
            else:
                raw = runner.bulk_result.raw if runner.bulk_result else None
                subject = {"eins": [normalize_ein(value) for value in runner.bulk_submitted]}
                absent = (
                    "this key restricts bulk EINs to an allowlist, so no bulk response "
                    "was returned"
                    if runner.free_tier_key
                    else "the bulk check did not return a response"
                )

            observed[kind] = (
                {"missing": absent}
                if raw is None
                else {"subject": subject, "signature": signature_of(raw)}
            )

        return observed[kind]

    def subject_mismatch(recorded: dict[str, Any], subject: dict[str, Any]) -> str | None:
        """
        A baseline recorded against a different organization, or a different batch,
        describes a different record. Comparing the two would report data variation
        as API drift, so the checks stand down instead.
        """
        if subject.get("ein") and recorded.get("ein") and recorded["ein"] != subject["ein"]:
            return (
                f"the baseline was recorded for EIN {recorded['ein']}, this run used "
                f"{subject['ein']}"
            )

        if subject.get("eins") and recorded.get("eins") and recorded["eins"] != subject["eins"]:
            return (
                f"the baseline was recorded for EINs {', '.join(recorded['eins'])}, "
                f"this run used {', '.join(subject['eins'])}"
            )

        return None

    def baseline_age(recorded: dict[str, Any], stored: dict[str, Any]) -> str:
        moment = parse_api_date(recorded.get("recorded_at") or stored.get("recorded_at"))

        if moment is None:
            return "baseline of unknown age"

        return f"baseline {age_in_days(moment)}d old"

    def against(
        kind: str,
        name: str,
        diff: Callable[[dict[str, str], dict[str, str]], Diff],
        describe: str,
    ) -> Check:
        """
        Both checks on an endpoint do the same work along different axes: signature
        of what arrived, held against the recorded one by ``diff``.

        With nothing recorded for this endpoint yet, there is nothing to hold it
        against, so this run becomes the baseline. That is the whole first-run
        ceremony: run it, and from the next run on the comparison is live.
        """

        def body(runner: Runner) -> Outcome:
            current = observe(runner, kind)

            if "missing" in current:
                return Outcome(status="skip", detail=str(current["missing"]))

            paths = len(current["signature"])
            stored = load_baseline()
            recorded = stored.get(kind) if isinstance(stored.get(kind), dict) else None

            if not recorded or not recorded.get("signature"):
                pending.add(kind)

                return Outcome(
                    detail=f"{paths} paths recorded — the next run checks against them",
                    data={"paths": paths},
                )

            mismatch = subject_mismatch(recorded, current["subject"])

            if mismatch:
                return Outcome(
                    status="skip", detail=f"{mismatch} — the two describe different records"
                )

            recorded_base_url = recorded.get("base_url") or stored.get("base_url")

            if (
                not announced_target[0]
                and recorded_base_url
                and recorded_base_url != runner.client.base_url
            ):
                announced_target[0] = True
                runner.note(
                    name,
                    f"the baseline was recorded against {recorded_base_url}; this run "
                    f"targeted {runner.client.base_url}, so a difference may be between "
                    "deployments rather than over time",
                )

            result = diff(recorded["signature"], current["signature"])

            check_that(
                result.total == 0,
                f"the live {kind} response no longer matches {baseline_path.name} — "
                f"{summarize_changes(result.changes)}\n{format_changes(result.changes)}\n"
                f"      delete {baseline_path.name} and re-run to re-record, "
                "once the change is understood and intended",
            )

            return Outcome(
                detail=f"{paths} {describe} · {baseline_age(recorded, stored)}",
                data={"paths": paths},
            )

        return Check((CONTRACT_GROUP_ID,), name, 0, body)

    def write_baseline(runner: Runner) -> Outcome:
        previous = load_baseline()
        written = [
            kind
            for kind in ("single", "bulk")
            if kind in pending and "signature" in observed[kind]
        ]

        if not written:
            return Outcome(
                status="skip",
                detail=f"{baseline_path.name} already covers what this run observed",
            )

        # Only what this run recorded is rewritten. An endpoint that was checked, or
        # that this run never reached, keeps the shape already on file — a failed
        # comparison must not quietly become the new baseline.
        def record_for(kind: str) -> Any:
            if kind not in written:
                return previous.get(kind)

            return {
                "recorded_at": datetime.now().isoformat(timespec="seconds"),
                "base_url": runner.client.base_url,
                "sdk_version": VERSION,
                **observed[kind]["subject"],
                "signature": observed[kind]["signature"],
            }

        kept = [
            kind
            for kind in ("single", "bulk")
            if kind not in written and isinstance(previous.get(kind), dict)
        ]

        baseline_path.write_text(
            json.dumps(
                {
                    "note": (
                        "Shape of the live API responses: path, JSON type and value format, "
                        "no values. Recorded on first run; delete this file and re-run to "
                        "re-record."
                    ),
                    "single": record_for("single"),
                    "bulk": record_for("bulk"),
                },
                indent=2,
            )
            + "\n",
            encoding="utf-8",
        )

        return Outcome(
            detail=(
                f"{' and '.join(written)} written to {baseline_path.name} — commit it"
                + (f" · {' and '.join(kept)} left as recorded" if kept else "")
            ),
            data={"written": written, "kept": kept},
        )

    return [
        against(
            "single", "single response schema", schema_diff, "paths, none added or removed"
        ),
        against(
            "single",
            "single response types",
            type_diff,
            "paths carry the recorded types and value formats",
        ),
        against("bulk", "bulk response schema", schema_diff, "paths, none added or removed"),
        against(
            "bulk",
            "bulk response types",
            type_diff,
            "paths carry the recorded types and value formats",
        ),
        Check((CONTRACT_GROUP_ID,), "baseline", 0, write_baseline),
    ]


# --- checks: rechecking the same record (ex-28..ex-30) -----------------------


def recheck_checks(ein: str) -> list[Check]:
    def _json(value: Any) -> str:
        return json.dumps(value, default=str, sort_keys=True)

    def a_repeat_check_is_stable(runner: Runner) -> Outcome:
        first = runner.single_result

        if not first or not first.nonprofit:
            return Outcome(status="skip", detail="the single check did not return a record")

        second = runner.client.nonprofits.check(ein)

        runner.observe_cycle_count(second.check_count)

        check_that(
            second.nonprofit is not None, "the same EIN returned no record on the second call"
        )

        before, after = record_of(first.nonprofit), record_of(second.nonprofit)

        check_that(
            after.get("ein") == before.get("ein"),
            "the two calls returned different EINs for the same request",
        )

        # A scheduled re-verification compares fields between runs. Fields that
        # appear and disappear between two calls seconds apart would make every
        # diff meaningless (ex-29, ex-30).
        appeared = [name for name in after if name not in before]
        vanished = [name for name in before if name not in after]
        changed = [
            name
            for name in before
            if name in after and _json(before[name]) != _json(after[name])
        ]

        drifts = (("appeared", appeared), ("vanished", vanished), ("changed", changed))

        for label, fields in drifts:
            if fields:
                runner.note(
                    "a repeat check is stable",
                    f"fields that {label} between two calls: {', '.join(fields)}",
                )

        distinct_ids = (
            first.request_id is not None
            and second.request_id is not None
            and first.request_id != second.request_id
        )

        if first.request_id is not None and not distinct_ids:
            runner.note(
                "a repeat check is stable",
                "both calls reported the same request id — an audit trail cannot tell "
                "them apart",
            )

        drifted = len(appeared) + len(vanished) + len(changed)

        return Outcome(
            status="warn" if drifted else "pass",
            detail=(
                (
                    f"{len(after)} fields identical across two calls"
                    if drifted == 0
                    else f"{drifted} field(s) differed between two calls seconds apart"
                )
                + f" · request ids {'distinct' if distinct_ids else 'not distinguishable'}"
            ),
            data={"appeared": appeared, "vanished": vanished, "changed": changed},
        )

    def check_count_is_cumulative(runner: Runner) -> Outcome:
        start, end = runner.cycle_count_start, runner.cycle_count_end

        if start is None or end is None:
            return Outcome(status="skip", detail="the API did not report nonprofit_check_count")

        check_that(end >= start, f"the counter went backwards: {start} → {end}")

        if end == start:
            # A free key reports the size of each request rather than a running
            # cycle total, so a flat counter is the documented behaviour for that
            # key class and proves nothing about the cumulative contract.
            if runner.free_tier_key:
                runner.note(
                    "check count is cumulative",
                    "the counter reported the size of each request and never accumulated "
                    f"({start} → {end}) — expected for a key with allowlisted EINs",
                )

                return Outcome(
                    status="skip",
                    detail="this key reports a per-request count — a cumulative total needs "
                    "a metered key",
                )

            runner.note(
                "check count is cumulative",
                f"the counter did not move across {runner.checks_spent} billable checks "
                f"({start} → {end})",
            )

            return Outcome(
                status="warn", detail=f"unchanged at {start} — expected a cumulative total"
            )

        return Outcome(
            detail=(
                f"{start} → {end} (+{end - start}) across the run · a running billing-cycle "
                "total, not a request size"
            ),
            data={"start": start, "end": end},
        )

    return [
        Check(
            ("ex-29", "ex-28", "ex-30"),
            "a repeat check is stable",
            1,
            a_repeat_check_is_stable,
        ),
        Check(("ex-21",), "check count is cumulative", 0, check_count_is_cumulative),
    ]


# --- checks: what actually went on the wire (ex-01, ex-17, ex-20) ------------


def wire_checks(api_key: str) -> list[Check]:
    single_pattern = re.compile(
        re.escape(SINGLE_CHECK_PATH).replace(re.escape("{ein}"), r"\d{9}") + "$"
    )

    def documented_endpoints_and_methods(runner: Runner) -> Outcome:
        if not runner.requests:
            return Outcome(status="skip", detail="no requests were sent")

        singles = 0
        bulks = 0

        for request in runner.requests:
            url = httpx.URL(request.url)

            check_that(url.query == b"", f"a request carried a query string: {url.query!r}")
            check_that(
                request.url.startswith(runner.client.base_url),
                f"a request went somewhere other than the configured host: {request.url}",
            )

            if request.method == "POST":
                check_that(
                    url.path == BULK_CHECK_PATH,
                    f"POST went to {url.path}, not BULK_CHECK_PATH",
                )
                check_that(
                    request.content_type == "application/json",
                    "the bulk request was not JSON",
                )

                body = json.loads(request.body or "null")

                check_that(isinstance(body, list), "the bulk body was not a JSON array of EINs")
                check_that(
                    all(re.fullmatch(r"\d{9}", value) for value in body),
                    "the bulk body carried EINs that were not normalized",
                )

                bulks += 1
            else:
                check_that(request.method == "GET", f"unexpected method {request.method}")
                check_that(
                    single_pattern.search(url.path) is not None,
                    f"GET went to {url.path}, not SINGLE_CHECK_PATH",
                )
                check_that(not request.body, "a GET carried a body")

                singles += 1

        return Outcome(
            detail=(
                f"{singles} GET on SINGLE_CHECK_PATH · {bulks} POST on BULK_CHECK_PATH · "
                "no query strings"
            ),
            data={"singles": singles, "bulks": bulks},
        )

    def credentials_stay_off_the_wire(runner: Runner) -> Outcome:
        if not runner.requests:
            return Outcome(status="skip", detail="no requests were sent")

        user_agent_prefix = "pactman-nonprofit-check-plus/"

        for request in runner.requests:
            check_that(
                not request.url_carries_key,
                f"the API key appeared in a request URL: {request.url}",
            )
            check_that(
                request.auth_carries_key,
                "a request went out without the key in its Authorization header",
            )
            check_that(
                request.auth_scheme == "Bearer",
                f'the Authorization header used the "{request.auth_scheme}" scheme',
            )
            check_that(
                request.accept == "application/json", f'Accept was "{request.accept}"'
            )
            check_that(
                (request.user_agent or "").startswith(user_agent_prefix)
                and VERSION in (request.user_agent or ""),
                f"the User-Agent does not identify this SDK version: {request.user_agent}",
            )

        # Belt and braces: the recorded log itself must be safe to print.
        check_that(
            api_key not in json.dumps([vars(request) for request in runner.requests]),
            "the recorded request log contains the API key",
        )

        return Outcome(
            detail=(
                f"{len(runner.requests)} requests · key in Authorization only · "
                f"UA {user_agent_prefix}{VERSION}"
            )
        )

    return [
        Check(
            ("ex-17", "ex-03"),
            "documented endpoints and methods",
            0,
            documented_endpoints_and_methods,
        ),
        Check(("ex-01",), "credentials stay off the wire", 0, credentials_stay_off_the_wire),
    ]


# --- checks: the disruptive probes (ex-22, ex-24) ----------------------------


def probe_checks(ein: str, api_key: str, base_url: str) -> list[Check]:
    """
    The two probes that misbehave on purpose: one starves a request of time, the
    other bursts until the server pushes back.

    They used to be opt-in, which meant the sign-off run routinely proved
    everything except the two paths a caller meets on their worst day. They are
    part of the plan now. The burst is bounded and stops the moment a 429 arrives.
    """

    async def cancel_mid_flight() -> str:
        """
        What ex-24 promises cancellation looks like: the task's own
        ``CancelledError``, never a PactmanError wearing its clothes.
        """
        async with AsyncPactmanClient(api_key=api_key, base_url=base_url) as client:
            task = asyncio.ensure_future(client.nonprofits.check(ein))

            await asyncio.sleep(0)
            task.cancel()

            try:
                await task
            except asyncio.CancelledError:
                return "CancelledError"
            except PactmanError as error:
                return type(error).__name__

        return "the request completed"

    def timeout_and_cancellation(runner: Runner) -> Outcome:
        timed_out = False

        # Short enough that the response cannot arrive, long enough that the
        # connection has been established — otherwise the socket fails first and
        # the SDK correctly reports a network error rather than a timeout.
        deadline = max(0.002, round((runner.observed_round_trip or 0.1) * 0.3, 3))

        try:
            runner.client.nonprofits.check(ein, timeout=deadline, retry=False)
        except PactmanTimeoutError as error:
            timed_out = True
            check_that(
                error.timeout == deadline,
                f"error.timeout was {error.timeout}, expected {deadline}",
            )
            check_that(
                error.origin == PactmanErrorOrigin.LOCAL,
                f'a timeout reported origin "{error.origin}"',
            )
        except PactmanNetworkError:
            timed_out = False

        cancelled = asyncio.run(cancel_mid_flight())

        check_that(
            cancelled == "CancelledError",
            f"a cancelled request raised {cancelled}, not asyncio.CancelledError",
        )

        if not timed_out:
            runner.note(
                "timeout and cancellation",
                f"a {deadline}s deadline produced a network error rather than a timeout — "
                "expected when the round trip is very short, as on a local host",
            )

        return Outcome(
            status="pass" if timed_out else "warn",
            detail=(
                f"{deadline}s deadline → "
                f"{'PactmanTimeoutError' if timed_out else 'a network error'} · "
                "cancel → asyncio.CancelledError"
            ),
        )

    def rate_limit(runner: Runner) -> Outcome:
        for attempt in range(1, RATE_LIMIT_ATTEMPTS + 1):
            try:
                result = runner.client.nonprofits.check(ein, retry=False)
            except PactmanRateLimitError as error:
                check_that(error.status == 429, f"expected status 429, got {error.status}")

                return Outcome(
                    detail=(
                        f"429 after {attempt} request(s) → PactmanRateLimitError · "
                        f"Retry-After {error.retry_after_seconds or 'not sent'}"
                    ),
                    data={"attempt": attempt},
                )

            runner.observe_cycle_count(result.check_count)

        return Outcome(
            status="warn",
            detail=(
                f"no 429 within {RATE_LIMIT_ATTEMPTS} sequential requests — "
                "the limit was not reached"
            ),
        )

    return [
        Check(
            ("ex-24", "async_concurrent"),
            "timeout and cancellation",
            2,
            timeout_and_cancellation,
        ),
        Check(("ex-22", "error_handling"), "rate limit", RATE_LIMIT_ATTEMPTS, rate_limit),
    ]


def build_plan(api_key: str, base_url: str) -> list[Check]:
    """
    The plan: every check in this file, in the order their results depend on.

    The record-derived checks read what the single check fetched, the contract
    checks read both responses, and the wire checks read the log every earlier
    check wrote — so this order is not the order the report is read in, and the
    report regroups it.

    Nothing here is conditional. Each entry declares its billable cost so the
    total can be printed before the first request goes out.
    """
    return [
        *client_checks(api_key),
        *local_validation_checks(EIN, api_key),
        *authentication_checks(EIN, base_url),
        *single_check_checks(EIN, api_key),
        *source_checks(),
        *forward_compatibility_checks(),
        *bulk_checks(BULK_EINS),
        *contract_checks(),
        *recheck_checks(EIN),
        *wire_checks(api_key),
        *probe_checks(EIN, api_key, base_url),
    ]


# --- the report --------------------------------------------------------------

# Column the detail text starts in, so the results read as two columns.
NAME_WIDTH = 34


def column(name: str, width: int = NAME_WIDTH) -> str:
    """A name in its column, never run together with the detail beside it."""
    return name.ljust(width) if len(name) < width else f"{name} "


def findings_by_check(findings: Sequence[Finding]) -> dict[str, list[str]]:
    """The observations each check recorded, keyed by the check that recorded them."""
    grouped: dict[str, list[str]] = {}

    for finding in findings:
        grouped.setdefault(finding.check, []).append(finding.message)

    return grouped


def print_report(groups: Sequence[Group], findings: Sequence[Finding]) -> None:
    """
    One heading per example file, and under it what this run has to say about what
    that file claims.

    A check that covers more than one example is printed in full under the first
    and referred to under the rest, so an example whose claim is proven somewhere
    else says where instead of looking untested — and nothing is counted twice.
    """
    observations = findings_by_check(findings)

    for group in groups:
        say(f"\n{group.id}  {group.title}")

        for result in group.primary:
            cost = f"  [{result.cost} check(s)]" if result.cost else ""
            say(f"  {STATUS[result.status]} {column(result.name)}{result.detail}{cost}")

            for message in observations.get(result.name, []):
                say(f"      · {message}")

        for result, under in group.secondary:
            say(
                f"  ↳ {STATUS[result.status]} "
                f"{column(result.name, NAME_WIDTH - 2)}checked under {under}"
            )

        if not group.primary and not group.secondary:
            say(f"  {STATUS['skip']} no check of its own — it composes examples checked above")


def print_summary(
    runner: Runner, examples: Sequence[Example], started_at: float
) -> None:
    counts = {
        status: sum(1 for result in runner.results if result.status == status)
        for status in ("pass", "fail", "warn", "skip")
    }
    groups = group_by_example(examples, runner.results)
    files = [group for group in groups if group.id != CONTRACT_GROUP_ID]
    own = sum(1 for group in files if group.primary)
    borrowed = sum(1 for group in files if not group.primary and group.secondary)
    start = runner.cycle_count_start
    end = runner.cycle_count_end
    delta = None if start is None or end is None else end - start
    counter = f"{'n/a' if start is None else start} → {'n/a' if end is None else end}"

    print_report(groups, runner.findings)

    say("\nSummary")
    say(
        f"  {len(runner.results)} checks: {counts['pass']} passed, {counts['fail']} failed, "
        f"{counts['warn']} warned, {counts['skip']} skipped"
    )
    say(
        f"  {len(files)} example files: {own} checked here, {borrowed} checked under another, "
        f"{len(files) - own - borrowed} with no check"
    )
    say(f"  {runner.requests_sent} HTTP requests · {runner.checks_spent} checks budgeted")
    say(
        f"  billing-cycle counter: {counter}"
        + ("" if delta is None else f"  (+{delta} actually billed)")
    )
    say(f"  {round((time.monotonic() - started_at) * 1000)}ms · SDK {VERSION}")


# --- main --------------------------------------------------------------------


def main() -> int:
    env_file = load_env_file()
    api_key = os.environ.get(API_KEY_ENV)

    if not api_key:
        print(
            f"No API key. Put {API_KEY_ENV} in python/.env, or export it, and run this again.",
            file=sys.stderr,
        )

        return 2

    _SECRETS.add(api_key)
    _SECRETS.add(INVALID_API_KEY)

    base_url = os.environ.get("PACTMAN_BASE_URL") or base_url_for_environment(
        DEFAULT_ENVIRONMENT
    )
    examples = discover_examples()
    plan = build_plan(api_key, base_url)
    planned_cost = sum(check.cost for check in plan)
    free_checks = sum(1 for check in plan if check.cost == 0)

    say(f"Target        {base_url}")
    say(f"Key           from {key_source(env_file)} ({len(api_key)} characters, never printed)")
    say(f"Subjects      {EIN} · bulk {', '.join(BULK_EINS)} · no record {MISSING_EIN}")
    say(
        f"Plan          {len(plan)} checks across {len(examples)} example files, "
        f"{free_checks} of them free"
    )
    say(f"Cost          {planned_cost} billable API checks, charged to this key")
    say()

    runner = Runner(api_key)
    started_at = time.monotonic()
    interrupted = False

    # Records every outbound request, so "nothing was sent" and "the key never left
    # the Authorization header" can be asserted rather than assumed.
    with httpx.Client(transport=RecordingTransport(runner), follow_redirects=True) as http:
        runner.client = PactmanClient(
            api_key=api_key,
            base_url=base_url,
            timeout=20.0,
            retry=RetryOptions(max_retries=2),
            http_client=http,
        )

        # The report cannot start until the last check is done, so the ticker is
        # what says the run is alive: one mark per check, in the order they run.
        print("Running       ", end="", flush=True)

        try:
            for check in plan:
                runner.run(check)
                print(STATUS[runner.results[-1].status], end="", flush=True)
        except KeyboardInterrupt:
            # A run stopped halfway still paid for what it sent, so it still reports.
            interrupted = True

    # Closes the ticker line.
    say()
    print_summary(runner, examples, started_at)

    if interrupted:
        return 130

    return 1 if any(result.status == "fail" for result in runner.results) else 0


if __name__ == "__main__":
    sys.exit(main())
