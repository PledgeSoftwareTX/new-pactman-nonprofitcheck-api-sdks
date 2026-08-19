# pactman-nonprofit-check-plus

Official Python SDK for the **Pactman Nonprofit Check Plus API**. Look up US nonprofits by EIN and read the IRS and OFAC findings behind the result.

- Typed models for every documented response field, with the raw payload always available
- Local EIN normalization and validation, so malformed input never costs a request
- A structured error taxonomy you branch on by type, never by parsing message strings
- Finite default timeout, cancellation, bounded retries with jittered backoff, and `Retry-After` support
- Sync and async clients with an identical surface

> **Server-side only.** Your API key is a private credential. Do not construct this client in anything that ships to an end user.

---

## Contents

- [Requirements](#requirements)
- [Installation](#installation)
- [Configuring your API key](#configuring-your-api-key)
- [Quick start](#quick-start)
- [Async](#async)
- [Environment and base URL](#environment-and-base-url)
- [Single check](#single-check)
- [Bulk check](#bulk-check)
- [Usage and billing cycle](#usage-and-billing-cycle)
- [Inspecting source-specific findings](#inspecting-source-specific-findings)
- [Response models and raw data](#response-models-and-raw-data)
- [EIN validation and normalization](#ein-validation-and-normalization)
- [Error handling](#error-handling)
- [Timeouts and cancellation](#timeouts-and-cancellation)
- [Retries](#retries)
- [Rate limits](#rate-limits)
- [Connection lifecycle](#connection-lifecycle)
- [Security](#security)
- [What this SDK does not tell you](#what-this-sdk-does-not-tell-you)
- [API reference](#api-reference)
- [Examples](#examples)
  - [Getting started](#getting-started) — EX-01 to EX-03
  - [Comparing and validating against the record](#comparing-and-validating-against-the-record) — EX-04, EX-05
  - [Reading the sources](#reading-the-sources) — EX-06 to EX-14
  - [Errors and edge cases](#errors-and-edge-cases) — EX-15, EX-16, EX-22 to EX-25
  - [Bulk](#bulk) — EX-17 to EX-21
  - [End-to-end workflows](#end-to-end-workflows) — EX-26 to EX-30
- [Development](#development)
- [Support](#support)
- [License](#license)

---

## Requirements

- Python **3.10 or newer**
- A Pactman API key with Nonprofit Check access

The only runtime dependency is [httpx](https://www.python-httpx.org), which backs both the sync and the async client. The package ships a `py.typed` marker, so mypy and Pyright see full types without a stub package.

## Installation

```bash
pip install pactman-nonprofit-check-plus
```

```bash
uv add pactman-nonprofit-check-plus
```

```bash
poetry add pactman-nonprofit-check-plus
```

## Configuring your API key

Load the key from the environment or a secret manager. Never commit it, never inline it in source, and never expose it to an end user.

```bash
# .env — excluded from version control
PACTMAN_API_KEY=your_api_key_here
```

```python
import os

from pactman_nonprofit_check_plus import PactmanClient

client = PactmanClient(api_key=os.environ["PACTMAN_API_KEY"])
```

The key is validated locally. A missing, empty, or whitespace-only key raises `PactmanConfigurationError` at construction, before any network call:

```python
PactmanClient(api_key="")
# PactmanConfigurationError: The Pactman API key is empty. Check that the
# environment variable holding it is set.
```

Every request carries the key as `Authorization: Bearer <key>`. It never appears in logs, error messages, `client.to_dict()`, or `repr(client)`.

## Quick start

```python
import os

from pactman_nonprofit_check_plus import PactmanClient

with PactmanClient(api_key=os.environ["PACTMAN_API_KEY"]) as client:
    result = client.nonprofits.check("41-1787097")

print(result.nonprofit["organization_name"])  # "EXAMPLE NONPROFIT"
print(result.nonprofit["pub78_verified"])     # True
print(result.check_count)                      # checks used so far this billing cycle
```

`result.nonprofit` is `None` when the API returned no record, so check it before subscripting.

## Async

`AsyncPactmanClient` has the same surface; only the call style differs.

```python
import asyncio
import os

from pactman_nonprofit_check_plus import AsyncPactmanClient


async def main() -> None:
    async with AsyncPactmanClient(api_key=os.environ["PACTMAN_API_KEY"]) as client:
        result = await client.nonprofits.check("41-1787097")
        print(result.nonprofit)


asyncio.run(main())
```

Every option, result type and exception in this document applies to both clients.

## Environment and base URL

Production is the default and the only named environment. Pactman's QA and sandbox hosts are internal and are not selectable from this package.

```python
from pactman_nonprofit_check_plus import PactmanClient, PactmanEnvironment

# These are equivalent.
PactmanClient(api_key=api_key)
PactmanClient(api_key=api_key, environment=PactmanEnvironment.PRODUCTION)
```

For a local mock server, a proxy, or a host Pactman has given you directly, set `base_url`. It overrides `environment`, and is validated locally — a malformed URL raises `PactmanConfigurationError` before a request is attempted.

```python
# Testing against a local mock.
client = PactmanClient(api_key=api_key, base_url="http://127.0.0.1:4010")

client.base_url    # "http://127.0.0.1:4010"
client.environment # None — an explicit host, not a named environment
```

Only the target host changes. Request and response semantics are identical.

## Single check

```python
result = client.nonprofits.check("41-1787097")

result.nonprofit      # Nonprofit | None
result.check_count    # nonprofit_check_count — see "Usage and billing cycle" below
result.time_taken_ms  # server-side processing time
result.status         # HTTP status
result.request_id     # correlation ID, when the server sends one
result.raw            # the unmodified response envelope
```

`"41-1787097"` and `"411787097"` are the same request — the EIN is normalized before the URL is built.

## Bulk check

```python
result = client.nonprofits.check_bulk(["41-1787097", "996589560", "999999999"])

for org in result.organizations:
    print(org["ein"], org["organization_name"])

# EINs with no record are not an error — they come back on a 200 response.
print(result.not_found_eins)  # ["999999999"]
print(result.check_count)
```

Behaviour worth knowing:

|                    |                                                                                                                            |
| ------------------ | -------------------------------------------------------------------------------------------------------------------------- |
| **Batch limit**    | 50 EINs per request, enforced locally before sending. Exported as `MAX_BULK_EINS`.                                         |
| **Chunking**       | None. Larger inputs raise rather than silently splitting into several billable requests.                                    |
| **Request order**  | Your EINs are sent exactly as supplied. The SDK never reorders them.                                                       |
| **Response order** | Not guaranteed to match. The API matches by set membership — index `organizations` by `ein`, never pair them positionally. |
| **Duplicates**     | Sent as supplied, because each one is billable. A repeated EIN still returns one record. Pass `dedupe=True` to collapse.    |
| **Empty input**    | Raises `PactmanValidationError` locally.                                                                                   |
| **A bare string**  | Rejected locally, so `check_bulk("411787097")` never iterates the characters of one EIN.                                    |
| **One bad EIN**    | The whole batch is rejected locally, identifying the failing index. Nothing is sent.                                        |
| **No matches**     | A batch where nothing matched is an error; a batch where some matched is a 200 with the rest in `not_found_eins`.          |

```python
# Opt in to deduplication.
client.nonprofits.check_bulk(eins, dedupe=True)

# Index by EIN — the pairing that always holds.
by_ein = {org["ein"]: org for org in result.organizations}
```

## Usage and billing cycle

`nonprofit_check_count`, surfaced as `result.check_count`, is the number of checks your account has consumed **so far in the current billing cycle**, including the request that returned it. It resets when a new cycle starts.

It is not the size of the request you just made. A bulk call for five EINs does not return `5`.

```python
before = client.nonprofits.check(ein)
after = client.nonprofits.check_bulk(eins)

after.check_count                          # cycle total, e.g. 1_284
after.check_count - before.check_count     # what these requests actually consumed
```

EINs with no matching record are not billed, so a delta can be smaller than the batch you sent. Read the number the API reports rather than reconstructing usage from your input.

## Inspecting source-specific findings

The API returns source fields flat on the organization (`pub78_*`, `bmf_*`, `ofac_*`, and the revocation fields). Read them directly, or use the grouped accessors — which copy fields 1:1 and derive nothing.

```python
from pactman_nonprofit_check_plus import get_aroe, get_bmf, get_ofac, get_pub78

result = client.nonprofits.check("41-1787097")
nonprofit = result.nonprofit

if nonprofit is not None:
    # IRS Publication 78
    pub78 = get_pub78(nonprofit)

    if pub78 is None:
        print("Publication 78 data was not returned for this organization.")
    else:
        print(pub78.get("verified"))     # True | False | None
        print(pub78.get("most_recent"))  # date of the Pub 78 record

    # IRS Business Master File
    bmf = get_bmf(nonprofit)
    print(bmf and bmf.get("status"), bmf and bmf.get("subsection_description"))

    # IRS Automatic Revocation of Exemption
    aroe = get_aroe(nonprofit)
    print(aroe and aroe.get("revocation_date"), aroe and aroe.get("reinstatement_date"))

    # OFAC Specially Designated Nationals
    ofac = get_ofac(nonprofit)
    print(ofac and ofac.get("status"))  # a sentence describing the finding
```

Each accessor returns `None` only when the API returned **no data at all** for that source. That keeps _"the source was not returned"_ distinct from an explicit negative such as `pub78_verified: False`.

**On OFAC:** the API returns `ofac_status` as prose, not a boolean. This SDK deliberately does not expose a `has_ofac_match` flag, because deriving one would mean pattern-matching English that could be reworded at any time. Read the status, or route it to a reviewer.

## Response models and raw data

Field names mirror the wire format exactly, so the API reference and your code use the same names — there is no rename table to keep in sync.

Wire models are `TypedDict`s, which are plain `dict`s at runtime. Unknown fields never break deserialization; anything the API adds in a future version is readable through the same object and through `raw`:

```python
from typing import Any, cast

result = client.nonprofits.check("411787097")

# Readable without an SDK upgrade. The cast is only for the type checker —
# the TypedDict describes what this release knows about, not what arrived.
record = cast(dict[str, Any], result.nonprofit)
record.get("some_future_field")

result.raw  # the complete, unmodified envelope
```

`None` and `False` are preserved as distinct values wherever the API distinguishes them.

## EIN validation and normalization

```python
from pactman_nonprofit_check_plus import is_valid_ein, normalize_ein, normalize_eins

normalize_ein("41-1787097")  # "411787097"
normalize_ein("411787097")   # "411787097"
is_valid_ein("4117870")      # False
```

Accepted: nine digits, with or without the conventional hyphen after the two-digit prefix, ignoring surrounding whitespace. Rejected: letters, other punctuation, wrong digit counts, empty and `None` values. No IRS prefix rules are applied.

Bulk validation reports every failure at once, by index:

```python
from pactman_nonprofit_check_plus import PactmanValidationError

try:
    client.nonprofits.check_bulk(["411787097", "nope", "1234"])
except PactmanValidationError as error:
    for issue in error.issues:
        print(issue.index, issue.value, issue.message)
```

> Formatting validation confirms only that a value is shaped like an EIN. It says nothing about tax-exempt status, identity, eligibility, or good standing.

## Error handling

Every failure is a `PactmanError` with a stable `category` and an `origin` of `local` or `api`. Branch on the class or the category — never on message text.

```python
from pactman_nonprofit_check_plus import (
    PactmanApiError,
    PactmanAuthenticationError,
    PactmanRateLimitError,
    PactmanTimeoutError,
    PactmanValidationError,
)

try:
    client.nonprofits.check(ein)
except PactmanValidationError:
    ...  # Bad input. Nothing was sent.
except PactmanAuthenticationError:
    ...  # The key was rejected.
except PactmanRateLimitError as error:
    print(error.retry_after_seconds)
except PactmanTimeoutError as error:
    print(error.timeout)
except PactmanApiError as error:
    print(error.status, error.request_id, error.api_errors)
```

| Class                        | Category         | Origin | Raised for                      |
| ---------------------------- | ---------------- | ------ | ------------------------------- |
| `PactmanConfigurationError`  | `configuration`  | local  | Unusable client options         |
| `PactmanValidationError`     | `validation`     | local  | Input rejected before sending   |
| `PactmanBadRequestError`     | `bad_request`    | api    | HTTP 400                        |
| `PactmanAuthenticationError` | `authentication` | api    | HTTP 401                        |
| `PactmanAuthorizationError`  | `authorization`  | api    | HTTP 403                        |
| `PactmanNotFoundError`       | `not_found`      | api    | HTTP 404                        |
| `PactmanRateLimitError`      | `rate_limit`     | api    | HTTP 429                        |
| `PactmanServerError`         | `server`         | api    | HTTP 5xx                        |
| `PactmanApiError`            | `api`            | api    | Any other unexpected response   |
| `PactmanTimeoutError`        | `timeout`        | local  | Exceeded the configured timeout |
| `PactmanNetworkError`        | `network`        | local  | No response at all              |

API errors carry `status`, `api_code`, `api_message`, `api_errors`, `request_id`, `retry_after_seconds`, `attempts`, and `raw`. When a body cannot be deserialized, the metadata is still preserved and `raw` holds what the server actually sent.

The underlying `httpx` exception is chained as `__cause__`, so `raise ... from` context survives into your traceback.

## Timeouts and cancellation

The default timeout is **30 seconds** per attempt, exported as `DEFAULT_TIMEOUT`. It is always finite — there is no way to disable it.

```python
client = PactmanClient(api_key=api_key, timeout=10.0)

# Or per request.
client.nonprofits.check(ein, timeout=5.0)
```

Timeouts are expressed in **seconds**, matching `httpx` and the rest of the Python ecosystem. (The Node SDK uses milliseconds; the defaults are the same 30 seconds either way.)

Cancellation is Python's own. With the async client, cancelling the surrounding task cancels the in-flight request _and_ any planned retries, and `asyncio.CancelledError` propagates untouched — it is never remapped into a `PactmanError`:

```python
task = asyncio.create_task(client.nonprofits.check(ein))
task.cancel()
```

To bound a whole operation including retries, wrap it:

```python
await asyncio.wait_for(client.nonprofits.check(ein), timeout=2.0)
```

## Retries

Enabled by default: up to **2 retries** (3 attempts total), exponential backoff from 0.5s with full jitter, capped at 8 seconds per delay.

```python
from pactman_nonprofit_check_plus import PactmanClient, RetryOptions

client = PactmanClient(
    api_key=api_key,
    retry=RetryOptions(
        max_retries=3,
        initial_delay=0.5,
        max_delay=8.0,
        backoff_factor=2.0,
        jitter=True,
        retryable_statuses=(429, 500, 502, 503, 504),
        respect_retry_after=True,
    ),
)

# Disable entirely.
PactmanClient(api_key=api_key, retry=False)

# Or override per request.
client.nonprofits.check(ein, retry={"max_retries": 0})
```

A `RetryOptions` replaces the policy outright; a **dict** merges onto the policy already in force. That is what lets `check(ein, retry={"max_retries": 1})` keep the client's other settings.

Retried: 429, 500, 502, 503, 504, and transient network failures. **Never** retried: 400, 401, 403, 404, and local validation errors — regardless of `retryable_statuses`. A valid `Retry-After` always takes precedence over computed backoff.

## Rate limits

The API returns HTTP 429 when you exceed your limit. The SDK maps that to `PactmanRateLimitError` and exposes `retry_after_seconds`.

```python
try:
    client.nonprofits.check(ein)
except PactmanRateLimitError as error:
    print(f"Retry in {error.retry_after_seconds or 'unknown'} seconds")
```

With retries enabled, a 429 is retried automatically after the server's `Retry-After`, falling back to backoff when none is sent.

An optional client-side ceiling is available and off by default:

```python
client = PactmanClient(api_key=api_key, max_requests_per_second=3)
```

Server-provided limits are authoritative and may vary by account and endpoint; treat this as a courtesy throttle, not a guarantee. For bulk workloads, prefer the bulk endpoint over concurrent single checks, and keep your own concurrency bounded — the SDK does not queue on your behalf.

## Connection lifecycle

The client owns an `httpx` connection pool. Use it as a context manager, or call `close()` / `aclose()`, so the pool is released:

```python
with PactmanClient(api_key=api_key) as client:
    client.nonprofits.check(ein)

async with AsyncPactmanClient(api_key=api_key) as client:
    await client.nonprofits.check(ein)
```

Build one client per process and share it — each instance carries its own throttle state and connection reuse. To control proxies, certificates or transports, pass your own `httpx` client; one you supply is never closed by this SDK:

```python
import httpx

client = PactmanClient(
    api_key=api_key,
    http_client=httpx.Client(proxy="http://proxy.internal:8080", verify="/etc/ssl/corp.pem"),
)
```

## Security

- Load the key from an environment variable or secret manager. Never commit it.
- **Server-side only.** The key must not reach an end user's device.
- The key is redacted from every diagnostic surface: error messages, `error.to_dict()`, `client.to_dict()`, `repr(client)`, and `str(client)`.
- Rotate the key if it is ever printed, logged, or committed.
- Nonprofit records may be subject to your own retention and privacy obligations. Storing responses is your call, not the SDK's.

## What this SDK does not tell you

The SDK exposes what the API returns and nothing more. It deliberately provides **no** composite `approved`, `eligible`, or `safe` verdict, and no boolean summarizing a source that the API does not itself express as a boolean.

A successful check is data, not a decision. Whether an organization qualifies for a grant, a donation, a match, or a partnership is a determination for your own legal, compliance, grantmaking, and risk policy.

## API reference

**Client** — `PactmanClient(...)` and `AsyncPactmanClient(...)`

| Option                    | Type                                   | Default        |                                                 |
| ------------------------- | -------------------------------------- | -------------- | ----------------------------------------------- |
| `api_key`                 | `str`                                  | —              | **Required.**                                   |
| `environment`             | `PactmanEnvironment \| str`            | `"production"` | Named environment.                              |
| `base_url`                | `str`                                  | —              | Explicit host; overrides `environment`.         |
| `timeout`                 | `float`                                | `30.0`         | Per-attempt timeout, in seconds.                |
| `retry`                   | `RetryOptions \| Mapping \| False`     | 2 retries      | Retry policy.                                   |
| `max_requests_per_second` | `float`                                | off            | Optional client-side throttle.                  |
| `default_headers`         | `Mapping[str, str]`                    | `{}`           | Extra headers; cannot override `Authorization`. |
| `http_client`             | `httpx.Client \| httpx.AsyncClient`    | created        | Custom HTTP client; never closed by the SDK.    |

Properties: `client.nonprofits`, `client.base_url`, `client.environment`, `client.timeout`, `client.to_dict()`.

**Methods**

- `client.nonprofits.check(ein, *, timeout=None, retry=None, headers=None)` → `SingleCheckResult`
- `client.nonprofits.check_bulk(eins, *, dedupe=False, timeout=None, retry=None, headers=None)` → `BulkCheckResult`

The async client returns awaitables from the same signatures.

**Helpers** — `normalize_ein`, `normalize_eins`, `is_valid_ein`, `get_pub78`, `get_bmf`, `get_aroe`, `get_ofac`, `supported_environments`, `base_url_for_environment`, `is_pactman_error`

**Constants** — `MAX_BULK_EINS`, `DEFAULT_TIMEOUT`, `DEFAULT_RETRY`, `DEFAULT_ENVIRONMENT`, `EIN_LENGTH`, `SINGLE_CHECK_PATH`, `BULK_CHECK_PATH`, `VERSION`

**Types** — `Nonprofit`, `OrganizationType`, `SingleCheckResult`, `BulkCheckResult`, `PactmanResult`, `ApiEnvelope`, `ApiErrorDetail`, `RetryOptions`, `ResolvedConfig`, `Pub78Source`, `BmfSource`, `AroeSource`, `OfacSource`, `ValidationIssue`

Every public member carries a docstring, so editor hover documentation works without leaving your code.

## Examples

Thirty numbered, runnable examples cover secure setup, every source on the response, each error and edge case, bulk semantics, and five end-to-end workflows.

Each one is reproduced below, condensed to the point it makes. Every snippet assumes the imports and a `client` from [Quick start](#quick-start), and omits the output formatting the runnable file uses. The full sources live in [`examples/`](https://github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks/tree/master/python/examples) in the repository — they read `PACTMAN_API_KEY` from the environment and contain no credentials.

```bash
git clone https://github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks.git
cd new-pactman-nonprofitcheck-api-sdks/python && pip install -e ".[dev]"

PACTMAN_API_KEY=your_key python examples/ex_01_secure_client_init.py
PACTMAN_API_KEY=your_key python examples/ex_03_identity_lookup.py 41-1787097
```

Examples for scenarios a live API will not produce on request — a revoked exemption, an OFAC match, an HTTP 429, a response carrying a field newer than this SDK — run against a bundled fixture server they start themselves. CI runs all thirty on every push:

```bash
python scripts/run_examples_against_mock.py                      # pass/fail
EXAMPLES_VERBOSE=1 python scripts/run_examples_against_mock.py   # with output
python scripts/run_examples_against_mock.py ex_22 ex_23          # a subset
```

Four shorter files sit alongside the numbered set for a first read: [`quickstart.py`](https://github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks/blob/master/python/examples/quickstart.py), [`bulk.py`](https://github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks/blob/master/python/examples/bulk.py), [`error_handling.py`](https://github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks/blob/master/python/examples/error_handling.py) and [`async_concurrent.py`](https://github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks/blob/master/python/examples/async_concurrent.py).

> **A note on `null` versus absent.** JavaScript separates `null` from `undefined`; Python has only `None`. Several examples below need that distinction — "the API returned null" and "the API returned no such field" route differently — so the shared helper in [`examples/lib/print.py`](https://github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks/blob/master/python/examples/lib/print.py) supplies a `NOT_RETURNED` sentinel and a `pick()` accessor that returns it. The snippets below use plain `.get()` where the difference does not matter, and `pick()` where it does.

### Getting started

#### EX-01 — Secure client initialization

Load the key from the environment, pick an environment, set a finite timeout, build one reusable client — and prove the key reaches no log, no exception, no debug output. [Full source](https://github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks/blob/master/python/examples/ex_01_secure_client_init.py)

```python
import os

from pactman_nonprofit_check_plus import PactmanClient, PactmanEnvironment

api_key = os.environ.get("PACTMAN_API_KEY")

if not api_key:
    raise RuntimeError("Set PACTMAN_API_KEY. Load it from your secret manager or an ignored .env.")

# One client, built once, reused for the life of the process. Constructing a
# client per request throws away connection reuse and any throttle state.
client = PactmanClient(
    api_key=api_key,
    environment=PactmanEnvironment.PRODUCTION,  # the default; naming it is explicit at review time
    timeout=10.0,  # the 30s default is often too long for a caller-facing service
)

# Every diagnostic surface, checked against the real key. None of them hold it.
surfaces = [repr(client), str(client), str(client.to_dict()), str(vars(client))]

any(api_key in text for text in surfaces)  # False
```

#### EX-02 — EIN normalization

A hyphenated, whitespace-padded EIN normalized to nine digits before the request, with the original kept for diagnostics. [Full source](https://github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks/blob/master/python/examples/ex_02_ein_normalization.py)

```python
from pactman_nonprofit_check_plus import is_valid_ein, normalize_ein

submitted = "  41-1787097  "  # what an onboarding form actually sends

is_valid_ein(submitted)   # True
normalize_ein(submitted)  # "411787097"

# Store the normalized form as your key — it is what the API echoes back — and
# keep the raw input beside it so support can see what the applicant typed.
applicant = {"ein_as_submitted": submitted, "ein": normalize_ein(submitted)}

# check() normalizes internally too, so either form is the same request.
result = client.nonprofits.check(applicant["ein_as_submitted"])

result.nonprofit["ein"]  # "411787097"
```

#### EX-03 — Identity lookup

EIN, name, AKA and Pactman profile URL, plus the raw envelope alongside the typed model. [Full source](https://github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks/blob/master/python/examples/ex_03_identity_lookup.py)

```python
result = client.nonprofits.check("41-1787097")

if result.nonprofit is not None:
    nonprofit = result.nonprofit

    nonprofit["ein"]
    nonprofit["organization_name"]
    nonprofit["organization_name_aka"]  # frequently null: "none on file", not "none exists"
    nonprofit["pactman_org_url"]

    # Response metadata.
    result.status
    result.request_id
    result.time_taken_ms
    result.check_count

    # The typed model is a view over the envelope, not a replacement for it.
    result.raw["code"]
    result.raw["message"]
    result.raw["data"]["ein"]
```

### Comparing and validating against the record

#### EX-04 — Applicant name comparison

Compare a submitted name with `organization_name` and `organization_name_aka` without treating punctuation or abbreviation differences as fraud. [Full source](https://github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks/blob/master/python/examples/ex_04_name_comparison.py)

```python
import re

# The SDK deliberately has no names_match(). What counts as a match is policy,
# so the comparison lives in customer code.
SUFFIXES = re.compile(r"\b(INC|INCORPORATED|CORP|CO|LLC|LTD|THE)\b\.?")


def normalize(name: object) -> str:
    text = SUFFIXES.sub("", str(name).upper())
    return re.sub(r"\s+", " ", re.sub(r"[^A-Z0-9 ]", " ", text)).strip()


nonprofit = client.nonprofits.check(applicant["ein"]).nonprofit or {}

candidates = [
    name
    for name in (nonprofit.get("organization_name"), nonprofit.get("organization_name_aka"))
    if isinstance(name, str)
]

if not candidates:
    outcome = "not_returned"  # no name came back — nothing was compared
elif any(normalize(name) == normalize(applicant["legal_name"]) for name in candidates):
    outcome = "agreement"
else:
    outcome = "mismatch"

# A mismatch is a reason to look, not a finding: organizations rebrand, file
# under a parent, and appear in IRS data under a name no donor would recognize.
routed = "continue" if outcome == "agreement" else "manual_review"
```

#### EX-05 — Validating the returned address

Ask whether the address the API returned is well-formed and self-consistent, before acting on it. [Full source](https://github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks/blob/master/python/examples/ex_05_address_validation.py)

```python
import re

from lib.print import NOT_RETURNED, pick

nonprofit = client.nonprofits.check(ein).nonprofit

# `state` and `state_name` are two fields for one fact, and the ZIP encodes the
# state a third time. A record can be complete and still contradict itself.
state = pick(nonprofit, "state")
state = None if state in (None, NOT_RETURNED) else str(state).strip().upper()
zip_digits = re.sub(r"\D", "", str(pick(nonprofit, "zip") or ""))

missing = [
    component
    for component in ("address_line1", "city", "state", "zip")
    if pick(nonprofit, component) in (None, NOT_RETURNED)
]

claimants = states_for_zip(zip_digits)

failures = [
    problem
    for problem in (
        None if state in US_STATES else "state is not a USPS code",
        None
        if US_STATES.get(state) == pick(nonprofit, "state_name")
        else "state_name disagrees with state",
        None if len(zip_digits) in (5, 9) else "zip is not 5 or 9 digits",
        # A check that cannot run reports nothing, never a failure: an incomplete
        # lookup table must not manufacture a finding about somebody's address.
        "zip belongs to another state" if claimants and state not in claimants else None,
    )
    if problem
]

# Three verdicts, and the middle one is the point. Absence is not validity.
verdict = "inconsistent" if failures else "incomplete" if missing else "usable"
routed = "continue" if verdict == "usable" else "manual_review"

# Well-formed is not deliverable. USPS, Lob, Smarty and Google Address
# Validation answer that one, over the network, with a second credential.
```

### Reading the sources

#### EX-06 — IRS Business Master File status

Every IRS Business Master File field on the response — status, identity, subsection, exemption, ruling, foundation. [Full source](https://github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks/blob/master/python/examples/ex_06_bmf_status.py)

```python
from pactman_nonprofit_check_plus import get_bmf

bmf = get_bmf(nonprofit)

if bmf is None:
    # Not "not in the BMF" — the API returned no BMF fields at all. That is an
    # absence of evidence, not a negative finding. Route it to review.
    ...
else:
    bmf.get("status")  # one source's answer to one question — there is no is_exempt here
    bmf.get("exempt_status_code")
    bmf.get("deductability_text")
    bmf.get("most_recent")

    bmf.get("organization_name"), bmf.get("ein"), bmf.get("street_address")
    bmf.get("city"), bmf.get("state"), bmf.get("church_message")
    bmf.get("subsection"), bmf.get("subsection_description")
    bmf.get("ruling_month"), bmf.get("ruling_year"), bmf.get("group_exemption")
    bmf.get("foundation_code"), bmf.get("foundation_code_description")
    bmf.get("foundation_type_code"), bmf.get("foundation_type_description")
    bmf.get("foundation_509a_status")
    bmf.get("filing_req_code"), bmf.get("pf_filing_req_cd")

# Reading the BMF in isolation is how a revoked or sanctioned organization
# passes a check — see EX-08 and EX-10.
```

#### EX-07 — Publication 78 and deductibility

Publication 78 verification and deductibility entries, with a donation policy applied in customer code. [Full source](https://github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks/blob/master/python/examples/ex_07_pub78_deductibility.py)

```python
from pactman_nonprofit_check_plus import get_pub78

pub78 = get_pub78(nonprofit) or {}

pub78.get("verified")  # True | False | None
pub78.get("indicator")
pub78.get("church_message")
pub78.get("most_recent")
pub78.get("source_org_type_1")  # …_2, …_3

for entry in pub78.get("organization_types") or []:
    entry.get("deductibility_status_description")
    entry.get("deductibility_limitation")
    entry.get("organization_type")

# Your policy, expressed against the source data. Change the predicate, not the
# SDK — nothing here is a verdict the API handed down.
ACCEPTED_LIMITATIONS = ["50%", "60%"]

limitations = [
    entry["deductibility_limitation"]
    for entry in pub78.get("organization_types") or []
    if entry.get("deductibility_limitation") is not None
]

eligible_under_this_policy = pub78.get("verified") is True and any(
    value in ACCEPTED_LIMITATIONS for value in limitations
)
```

#### EX-08 — Automatic revocation detected

An organization in the IRS Automatic Revocation data, flagged and recorded with its source fields. [Full source](https://github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks/blob/master/python/examples/ex_08_automatic_revocation.py)

```python
from datetime import datetime, timezone

from pactman_nonprofit_check_plus import get_aroe

aroe = get_aroe(nonprofit) or {}
revoked = bool(aroe.get("revocation_code")) or bool(aroe.get("revocation_date"))

# The application's policy, in one place, expressed against source fields.
if not revoked:
    action = "continue"
elif aroe.get("reinstatement_date"):
    action = "manual_review"
else:
    action = "block"

# What you keep is what you can explain later. Store the source fields, the
# request identifier and the time you looked — not just the verdict.
AUDITED = [
    "revocation_code",
    "revocation_date",
    "reinstatement_date",
    "aroe_list_published_date",
    "bmf_status",      # revocation shows up in the other sources too
    "pub78_verified",
]

audit_record = {
    "ein": nonprofit["ein"],
    "checked_at": datetime.now(timezone.utc).isoformat(),
    "request_id": result.request_id,
    "action": action,
    # Absent keys stay absent, so the record cannot imply a null the API never sent.
    "source_findings": {key: nonprofit[key] for key in AUDITED if key in nonprofit},
}
```

#### EX-09 — Revocation with reinstatement

Revocation and reinstatement dates kept separate, and the questions reinstatement does not answer. [Full source](https://github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks/blob/master/python/examples/ex_09_revocation_reinstatement.py)

```python
from datetime import datetime

aroe = get_aroe(nonprofit) or {}


def parse(value: object) -> datetime | None:
    """The API formats dates as `M/DD/YYYY h:mm:ss AM`. Parse; never reformat in place."""
    if not value:
        return None

    try:
        return datetime.strptime(str(value), "%m/%d/%Y %I:%M:%S %p")
    except ValueError:
        return None


revoked_at = parse(aroe.get("revocation_date"))
reinstated_at = parse(aroe.get("reinstatement_date"))

# Nothing collapses the two into a "currently revoked" boolean — that boolean
# would lose the interval, and donations dated inside it may need handling.
if revoked_at and reinstated_at:
    lapsed_days = (reinstated_at - revoked_at).days

# Reinstatement resolves one question, not every question: was it retroactive?
# Do gifts made during the lapse need re-characterizing? Does your grant
# agreement require continuous exemption? This record still goes to review.
```

#### EX-10 — OFAC screening result

Four distinct OFAC outcomes — no match, match, null, and not screened at all. [Full source](https://github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks/blob/master/python/examples/ex_10_ofac_screening.py)

```python
import re

from lib.print import NOT_RETURNED, pick

from pactman_nonprofit_check_plus import Nonprofit, get_ofac


# The SDK exposes no has_ofac_match boolean: deriving one means pattern-matching
# English the source can reword at any time. The one textual test below
# escalates and never clears — anything unrecognized falls through to review.
def classify_ofac(nonprofit: Nonprofit) -> str:
    ofac = get_ofac(nonprofit)

    if ofac is None:
        return "unavailable"  # no OFAC field at all; nothing was screened

    status = pick(ofac, "status")

    if status is None or status is NOT_RETURNED:
        return "null"
    if re.search(r"UID:", str(status), re.IGNORECASE):
        return "match"
    if re.search(r"NOT included", str(status), re.IGNORECASE):
        return "no_match"

    return "needs_review"


# Four states, four destinations. None of them is "approve automatically".
ROUTING = {
    "no_match": "continue — screened against the SDN list with no match",
    "match": "block and escalate to compliance",
    "null": "hold — the field was returned empty; treat as unscreened, not as cleared",
    "unavailable": "hold — no OFAC data was returned",
    "needs_review": "hold — the status text was not recognized by this application",
}

ROUTING[classify_ofac(nonprofit)]
```

#### EX-11 — Cross-source conflict

`irs_bmf_pub78_conflict` handled by recording both sources, not by picking one. [Full source](https://github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks/blob/master/python/examples/ex_11_source_conflict.py)

```python
bmf = get_bmf(nonprofit) or {}
pub78 = get_pub78(nonprofit) or {}
findings = []

# The flag the API sets is authoritative; the comparisons only explain it.
if nonprofit.get("irs_bmf_pub78_conflict") is True:
    findings.append("The API flagged a BMF / Publication 78 disagreement.")

if bmf.get("status") is True and pub78.get("verified") is False:
    findings.append("The BMF lists the organization as exempt; Publication 78 does not list it.")

if bmf.get("status") is False and pub78.get("verified") is True:
    findings.append("Publication 78 lists the organization; the BMF does not show it as exempt.")

# Both sides are kept, side by side, for the reviewer. Silently preferring one
# source means being wrong for some organization with the evidence destroyed.
review_record = (
    {
        "ein": nonprofit["ein"],
        "request_id": result.request_id,
        "findings": findings,
        "sources": {"bmf": bmf, "pub78": pub78},
    }
    if findings
    else None
)
```

#### EX-12 — Organization type and foundation classification

Organization types, foundation and subsection classification for a grantmaker or DAF display. [Full source](https://github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks/blob/master/python/examples/ex_12_foundation_classification.py)

```python
bmf = get_bmf(nonprofit) or {}
pub78 = get_pub78(nonprofit) or {}

# What a grant officer sees. Every value is copied, none is computed — and the
# descriptions come from the API's own *_description fields, which stay correct
# when the source changes. A lookup table in your repository does not.
classification_panel = {
    "subsection": bmf.get("subsection_description"),
    "foundation_code": bmf.get("foundation_code_description"),
    "foundation_type": bmf.get("foundation_type_description"),
    "status_509a": bmf.get("foundation_509a_status"),
    "deductibility": bmf.get("deductability_text"),
    "entries": pub78.get("organization_types"),
}

# A private foundation grantee is not disqualified — it is routed differently,
# because expenditure responsibility and the deductibility limit both change.
is_private_foundation = (
    bmf.get("foundation_type_code") == "pf" or bmf.get("pf_filing_req_cd") == "1"
)
```

#### EX-13 — Filing and exemption metadata

Filing and exemption codes preserved exactly, or mapped through documented tables with an unknown-value fallback. [Full source](https://github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks/blob/master/python/examples/ex_13_filing_exemption_metadata.py)

```python
from typing import Any

FILING_REQUIREMENTS = {
    "01": "990 (all other) or 990-EZ return",
    "02": "990 - Required to file Form 990-N",
}


def describe(table: dict[str, str], code: Any) -> dict[str, Any]:
    """A documented table with an explicit unknown fallback.

    A value the IRS adds reads as "unrecognized" — never as a blank, and never
    as the wrong label.
    """
    if code is None or code is NOT_RETURNED:
        return {"code": code, "known": False, "display": "<not returned>"}

    description = table.get(code)

    return {
        "code": code,
        "known": description is not None,
        "display": description or f'unrecognized code "{code}"',
    }


bmf = get_bmf(nonprofit) or {}

describe(FILING_REQUIREMENTS, bmf.get("filing_req_code"))

# Codes the API already describes for you: read its description, do not shadow
# it with a local table that will drift.
bmf.get("subsection"), bmf.get("subsection_description")
bmf.get("foundation_code"), bmf.get("foundation_code_description")
bmf.get("ruling_month"), bmf.get("ruling_year")  # raw values, preserved exactly, null included

# Never coerce an unrecognized code to a default. "Unknown" is a real state,
# and it usually means review rather than approval.
```

#### EX-14 — Data freshness and report metadata

Source timestamps, report date and request timing, feeding an application-owned re-review rule. [Full source](https://github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks/blob/master/python/examples/ex_14_data_freshness.py)

```python
from datetime import datetime, timezone

# Your rule. The SDK has no is_stale and no default threshold, because 90 days
# is prudent for one workflow and reckless for another.
RE_REVIEW_AFTER_DAYS = 90

timestamps = {
    "organization_info_last_modified": nonprofit.get("organization_info_last_modified"),
    "report_date": nonprofit.get("report_date"),        # when this response was generated
    "most_recent_bmf": nonprofit.get("most_recent_bmf"),  # when each list was last refreshed
    "most_recent_pub78": nonprofit.get("most_recent_pub78"),
    "ofac_list_published_date": nonprofit.get("ofac_list_published_date"),
    "aroe_list_published_date": nonprofit.get("aroe_list_published_date"),
}

now = datetime.now()
ages = {
    name: (now - parsed).days if (parsed := parse(value)) else None
    for name, value in timestamps.items()
}

undated = [name for name, age in ages.items() if age is None]
oldest = max((age for age in ages.values() if age is not None), default=0)

# The oldest source governs, and an undated source is not a fresh one.
needs_re_review = oldest > RE_REVIEW_AFTER_DAYS or bool(undated)

# Store the timestamps with the verification record, not just the outcome. "We
# checked and it was fine" is not an answer six months later; "we checked on
# this date against BMF data published on that date" is.
evidence = {
    "ein": nonprofit["ein"],
    "checked_at": datetime.now(timezone.utc).isoformat(),
    "request_id": result.request_id,
    **timestamps,
}
```

### Errors and edge cases

#### EX-15 — Malformed EIN rejected locally

Every malformed shape rejected locally, with an instrumented transport proving no request was sent. [Full source](https://github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks/blob/master/python/examples/ex_15_malformed_ein.py)

```python
import httpx

from pactman_nonprofit_check_plus import PactmanClient, PactmanValidationError


class CountingTransport(httpx.BaseTransport):
    """A counting wrapper around the real transport, to prove the claim rather
    than assert it. If any call below reaches the network, this number moves."""

    def __init__(self, inner: httpx.BaseTransport) -> None:
        self._inner = inner
        self.requests_sent = 0

    def handle_request(self, request: httpx.Request) -> httpx.Response:
        self.requests_sent += 1
        return self._inner.handle_request(request)


transport = CountingTransport(httpx.HTTPTransport())
client = PactmanClient(api_key=api_key, http_client=httpx.Client(transport=transport))

bad = ["41178709", "4117870977", "41-178709A", "", "   ", None, 411787097, ["411787097"],
       "41.1787097", "411-787097"]

for value in bad:
    try:
        client.nonprofits.check(value)
    except PactmanValidationError as error:
        error.origin      # PactmanErrorOrigin.LOCAL
        error.issues[0]   # index, value, message — enough to highlight the form field

# Bulk reports every failure at once, by index.
try:
    client.nonprofits.check_bulk(["411787097", "nope", "996589560"])
except PactmanValidationError as error:
    error.issues

transport.requests_sent  # 0 — bad input costs no quota, no latency, no rate-limit budget
```

#### EX-16 — EIN not found

A well-formed EIN with no record: `PactmanNotFoundError`, sanitized diagnostics, and why bulk behaves differently. [Full source](https://github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks/blob/master/python/examples/ex_16_not_found.py)

```python
from pactman_nonprofit_check_plus import (
    PactmanApiError,
    PactmanNotFoundError,
    is_pactman_error,
)

try:
    client.nonprofits.check("999999999")
except PactmanNotFoundError as error:
    # Stable identity: class, category, origin. Never parse `message`.
    error.category                        # PactmanErrorCategory.NOT_FOUND
    error.origin                          # PactmanErrorOrigin.API
    isinstance(error, PactmanApiError)    # True — catch the specific case or the general one
    is_pactman_error(error)               # True

    # The envelope's own detail survives onto the error.
    error.status, error.api_code, error.api_message, error.request_id, error.api_errors
    error.attempts  # 1 — not-found is not a transient failure, so it is never retried

    error.to_dict()  # sanitized: safe to log, safe to attach to a support ticket

# The bulk endpoint behaves differently: unmatched EINs come back on a 200.
mixed = client.nonprofits.check_bulk(["411787097", "999999999"])

mixed.status           # 200
mixed.not_found_eins   # ["999999999"]

# Only a request where nothing at all matched is a 404.
```

#### EX-22 — Rate limits and `Retry-After`

HTTP 429, `Retry-After`, bounded retries, a client-side rate ceiling and a bounded worker pool. [Full source](https://github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks/blob/master/python/examples/ex_22_rate_limit.py)

```python
from datetime import datetime, timedelta, timezone

from pactman_nonprofit_check_plus import PactmanClient, PactmanRateLimitError

# 1. Retries off, so the 429 reaches the caller untouched.
try:
    client.nonprofits.check(ein, retry=False)
except PactmanRateLimitError as error:
    error.status                # 429
    error.retry_after_seconds   # the server's number, when it sent one
    error.request_id, error.attempts, error.api_errors

    # Schedule your own backoff from the server's number; fall back when absent.
    wait = error.retry_after_seconds if error.retry_after_seconds is not None else 5
    retry_at = datetime.now(timezone.utc) + timedelta(seconds=wait)

# 2. Bounded automatic retry. Retry-After wins over computed backoff, and
#    retries stay finite — the SDK never retries indefinitely.
client.nonprofits.check(ein, retry={"max_retries": 1, "respect_retry_after": True})

# 3. Reduce pressure rather than absorb rejections: cap the outbound rate, keep
#    your own concurrency small, and prefer one bulk call to a fan-out of
#    single ones. The SDK throttles, but it does not queue on your behalf.
paced = PactmanClient(api_key=api_key, max_requests_per_second=3, retry={"max_retries": 2})
```

#### EX-23 — Transient failures and retries

Transient 5xx and connection failures retried with jittered backoff; auth, validation and not-found never retried. [Full source](https://github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks/blob/master/python/examples/ex_23_transient_retries.py)

```python
from pactman_nonprofit_check_plus import PactmanNetworkError, PactmanNotFoundError

# Two 503s absorbed, one successful result returned to the caller. Backoff
# grows exponentially and is jittered, so parallel clients scatter.
result = client.nonprofits.check(
    ein, retry={"max_retries": 3, "initial_delay": 0.5, "max_delay": 8.0}
)

# Never retried, whatever retryable_statuses contains. Retrying a 404 cannot
# make a record exist; retrying a rejected key just burns it three times.
try:
    client.nonprofits.check(
        missing_ein, retry={"max_retries": 5, "retryable_statuses": (404, 500)}
    )
except PactmanNotFoundError as error:
    error.attempts  # 1

# A connection that never reached a server: retried, then surfaced with the
# attempt count. Local validation never reaches the network at all.
try:
    unreachable.nonprofits.check(ein)
except PactmanNetworkError as error:
    error.attempts
    error.__cause__  # the underlying httpx exception, chained

# A retried failure that exhausts its budget is an outage. Record it as "not
# checked", never as a pass.
```

#### EX-24 — Timeouts and cancellation

`PactmanTimeoutError` and asyncio cancellation kept distinguishable, with no work left running. [Full source](https://github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks/blob/master/python/examples/ex_24_timeout_and_cancellation.py)

```python
import asyncio

from pactman_nonprofit_check_plus import PactmanTimeoutError

# Two different events, two different types. Conflating them hides which side
# gave up: a timeout means raise the budget or shed load; a cancellation means
# the caller went away.
try:
    client.nonprofits.check(ein, timeout=0.25, retry=False)
except PactmanTimeoutError as error:
    error.timeout   # the deadline you configured expired, in seconds
    error.category  # PactmanErrorCategory.TIMEOUT, origin LOCAL

# Cancellation is Python's own, and is never remapped into a PactmanError.
task = asyncio.create_task(async_client.nonprofits.check(ein))
await asyncio.sleep(0.2)
task.cancel()

try:
    await task
except asyncio.CancelledError:
    # Cancelling ends the in-flight attempt and every retry still planned;
    # cancelling before the call means no request is made at all.
    ...

# To bound a whole operation, including retries, wrap it.
await asyncio.wait_for(async_client.nonprofits.check(ein), timeout=2.0)
```

#### EX-25 — Raw response and forward compatibility

An approved fixture from a newer API version: unknown fields and an unknown enum value, both readable, neither fatal. [Full source](https://github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks/blob/master/python/examples/ex_25_raw_and_forward_compat.py)

```python
from typing import Any, cast

result = client.nonprofits.check(ein)
nonprofit = result.nonprofit

# Known fields deserialize exactly as they always have.
bmf = get_bmf(nonprofit) or {}
bmf.get("status")

# Fields this SDK version does not declare ride along on the same dict. The
# TypedDict describes what this release knows about, so reach the rest through a
# dict view and narrow them deliberately. No upgrade needed.
record = cast(dict[str, Any], nonprofit)
registration = record.get("state_charity_registration_status")

if isinstance(registration, str):
    ...

# An unrecognized value in a documented field. This is the case that breaks
# applications which map eagerly into an enum and default the miss.
KNOWN_FOUNDATION_TYPES = {"pc", "pf", "po"}
foundation_type = bmf.get("foundation_type_code")

handled = (
    "a known classification"
    if foundation_type in KNOWN_FOUNDATION_TYPES
    else "unknown — routed to review, not defaulted to a known type"
)

result.raw                        # the parsed body, unmodified — persist it as evidence
result.raw["data"] is nonprofit   # True
```

### Bulk

#### EX-17 — Bulk screening of a list

Screening a grantee list, iterating organization-level results and reading the response envelope. [Full source](https://github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks/blob/master/python/examples/ex_17_bulk_screening.py)

```python
from pactman_nonprofit_check_plus import get_aroe, get_bmf, get_ofac, get_pub78

# One bulk request is one round trip and one rate-limit slot. Prefer it to a
# loop of single checks.
result = client.nonprofits.check_bulk([entry["ein"] for entry in portfolio])

result.status, result.raw["code"], result.time_taken_ms, result.check_count
len(result.organizations), len(result.errors), result.not_found_eins

# Index by EIN. The response is a set of matched records, not a row-for-row
# answer to your input list — see EX-18.
by_ein = {org["ein"]: org for org in result.organizations}

for entry in portfolio:
    org = by_ein.get(entry["ein"])

    if org is None:
        continue  # no record returned — not a pass

    bmf = get_bmf(org) or {}
    pub78 = get_pub78(org) or {}
    aroe = get_aroe(org) or {}
    ofac = get_ofac(org) or {}

    print(
        org["ein"],
        bmf.get("status"),
        pub78.get("verified"),
        bool(aroe.get("revocation_date")),
        ofac.get("status"),
    )

for detail in result.errors:
    detail.get("resource"), detail.get("code"), detail.get("reason"), detail.get("eins")
```

#### EX-18 — Input order and duplicate EINs

Response order does not follow request order, duplicates collapse in the response but still bill, and usage is read rather than inferred. [Full source](https://github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks/blob/master/python/examples/ex_18_bulk_order_and_duplicates.py)

```python
# Deliberately unsorted, with one EIN repeated. The SDK sends them exactly as
# supplied: it does not reorder and it does not deduplicate.
requested = ["996589560", "411787097", "996589560", "135562308"]

before = client.nonprofits.check("411787097")
result = client.nonprofits.check_bulk(requested)

len(result.organizations)  # 3 — the duplicate came back once

# Positional pairing is invalid. This is the pairing that always holds.
by_ein = {org["ein"]: org for org in result.organizations}

# Usage is reported, not inferred. Every submitted EIN is billable, duplicates
# included, so a count derived from unique inputs will disagree with the invoice.
(result.check_count or 0) - (before.check_count or 0)

# Opt in when duplicates are an artifact of your data rather than intent.
client.nonprofits.check_bulk(requested, dedupe=True)
```

#### EX-19 — Partial success and item-level errors

Mixed outcomes on one HTTP 200: usable records, item-level errors, and a full input reconciliation. [Full source](https://github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks/blob/master/python/examples/ex_19_bulk_partial_success.py)

```python
submitted = ["411787097", "999999999", "996589560", "123456789"]
result = client.nonprofits.check_bulk(submitted)

result.status          # 200 — some matched and some did not, which is a success
result.organizations   # ordinary records; nothing about a sibling failure degrades them
result.errors          # [{"resource": ..., "code": ..., "reason": ..., "eins": [...]}]
result.not_found_eins

# Reconcile every input against an outcome. This is the loop that keeps a
# portfolio import honest.
matched = {org["ein"] for org in result.organizations}
missing = set(result.not_found_eins)

for ein in submitted:
    if ein in matched:
        outcome = "matched"
    elif ein in missing:
        outcome = "no record — reported in errors"
    else:
        outcome = "UNACCOUNTED FOR — do not treat as checked"

# An EIN the API has no record for is a gap in the data, not a negative finding
# about the organization. Route it to review; do not record it as "screened".
```

#### EX-20 — Batch-size validation and chunking

Empty and over-limit batches rejected against `MAX_BULK_EINS`, plus chunking a larger list yourself. [Full source](https://github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks/blob/master/python/examples/ex_20_bulk_batch_limits.py)

```python
from pactman_nonprofit_check_plus import (
    MAX_BULK_EINS,
    PactmanBadRequestError,
    PactmanValidationError,
)

MAX_BULK_EINS  # 50 — import it; do not copy the number into your own constants file

try:
    client.nonprofits.check_bulk([])          # empty
    client.nonprofits.check_bulk(oversized)   # MAX_BULK_EINS + 1
except PactmanValidationError as error:
    error.origin  # PactmanErrorOrigin.LOCAL — nothing was sent

# If the server ever tightens its limit below the SDK's constant, the local
# check passes and the server answers 400. That message is authoritative:
# catch PactmanBadRequestError and log api_errors[]["reason"] verbatim.

# The SDK never chunks for you, because splitting one batch would quietly turn
# one billable request into several. Do it deliberately.
batches = [eins[index : index + MAX_BULK_EINS] for index in range(0, len(eins), MAX_BULK_EINS)]
```

#### EX-21 — Billing-cycle usage tracking

`nonprofit_check_count` as a cumulative billing-cycle total that resets each cycle — never a per-request size. [Full source](https://github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks/blob/master/python/examples/ex_21_usage_tracking.py)

```python
import os

first = client.nonprofits.check(ein_a)
bulk = client.nonprofits.check_bulk([ein_a, ein_b, ein_c])

first.check_count                                # cycle total, e.g. 1_281
bulk.check_count                                 # cycle total again, e.g. 1_284 — not 3
(bulk.check_count or 0) - (first.check_count or 0)  # what the bulk call consumed

# EINs with no record are not billed, so a delta can be smaller than the batch.
# At the start of a new billing cycle this counter resets to zero.

# Alerting needs your plan's allowance, which the check endpoints do not
# report. Keep it in your own configuration.
allowance = int(os.environ.get("PACTMAN_PLAN_ALLOWANCE") or 0)
utilisation = (bulk.check_count or 0) / allowance if allowance > 0 else None

# Label this metric "checks used this billing cycle" wherever it is displayed.
# Labelling it "checks in this request" makes a dashboard that resets monthly
# look like a dashboard that is broken.
```

### End-to-end workflows

#### EX-26 — Donation-platform onboarding

Donation-platform onboarding: collect, check, inspect every source, route to approve, reject or review. [Full source](https://github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks/blob/master/python/examples/ex_26_onboarding_workflow.py)

```python
import re
from typing import Any

from pactman_nonprofit_check_plus import PactmanError, get_aroe, get_ofac, get_pub78

# This fictional platform's rules, in one place, reviewable by its compliance
# team. Read them as an illustration of where your policy lives.
STALE_AFTER_DAYS = 120
REQUIRE_PUB78_LISTING = True


def onboard(applicant: dict[str, Any]) -> dict[str, Any]:
    try:
        result = client.nonprofits.check(applicant["ein"])
    except PactmanError:
        # A failed lookup is not a rejection. Nothing was learned, so nothing can
        # be concluded — the applicant waits, they are not turned away.
        return {"decision": "manual_review", "reasons": ["the check could not be completed"]}

    nonprofit = result.nonprofit

    if nonprofit is None:
        return {"decision": "manual_review", "reasons": ["no record for this EIN"]}

    aroe = get_aroe(nonprofit) or {}
    ofac = get_ofac(nonprofit) or {}
    pub78 = get_pub78(nonprofit) or {}
    reasons: list[str] = []

    if aroe.get("revocation_date") and not aroe.get("reinstatement_date"):
        return {"decision": "reject", "reasons": ["Exemption revoked with no reinstatement."]}

    status = ofac.get("status")

    if isinstance(status, str) and re.search(r"UID:", status, re.IGNORECASE):
        return {"decision": "reject", "reasons": ["Possible OFAC SDN match."]}

    if nonprofit.get("irs_bmf_pub78_conflict") is True:
        reasons.append("IRS sources disagree.")

    if REQUIRE_PUB78_LISTING and pub78.get("verified") is not True:
        reasons.append("Not listed in Publication 78.")

    if not name_agrees(applicant["legal_name"], nonprofit):
        reasons.append("Submitted name did not match.")

    if not reasons:
        return {
            "decision": "approve",
            "reasons": ["Every check this platform requires was satisfied."],
        }

    return {"decision": "manual_review", "reasons": reasons}


# The platform decided; the SDK did not.
```

#### EX-27 — DAF grant-recommendation screening

DAF grant-recommendation screening, with a stricter policy than EX-26 over identical data. [Full source](https://github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks/blob/master/python/examples/ex_27_daf_grant_screening.py)

```python
import re
from datetime import datetime, timezone

# One bulk call for the whole recommendation batch.
result = client.nonprofits.check_bulk([entry["ein"] for entry in recommendations])
by_ein = {org["ein"]: org for org in result.organizations}
decisions = []

for recommendation in recommendations:
    org = by_ein.get(recommendation["ein"])

    if org is None:
        # No record was returned. Nothing was verified.
        decisions.append({**recommendation, "outcome": "held", "queue": "grants_review"})
        continue

    aroe = get_aroe(org) or {}
    ofac = get_ofac(org) or {}
    bmf = get_bmf(org) or {}

    status = ofac.get("status")
    sanctioned = isinstance(status, str) and re.search(r"UID:", status, re.IGNORECASE)

    if sanctioned:
        outcome, queue = "blocked", "sanctions_review"
    elif aroe.get("revocation_date") and not aroe.get("reinstatement_date"):
        outcome, queue = "blocked", "tax_status_review"
    elif org.get("irs_bmf_pub78_conflict") is True:
        outcome, queue = "held", "source_conflict_review"
    elif bmf.get("foundation_type_code") == "pf":
        outcome, queue = "held", "expenditure_responsibility"  # not refused: a different path
    else:
        outcome, queue = "advanced", "ready_for_approval"

    decisions.append(
        {
            **recommendation,
            "outcome": outcome,
            "queue": queue,
            "screened_at": datetime.now(timezone.utc).isoformat(),
            "request_id": result.request_id,
        }
    )

# Same API data as EX-26, different obligations, different outcomes. That
# difference is precisely why the SDK does not decide.
```

#### EX-28 — CRM enrichment and synchronization

CRM sync keyed on EIN, where a null from the API never erases better customer data. [Full source](https://github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks/blob/master/python/examples/ex_28_crm_enrichment.py)

```python
from datetime import datetime, timezone
from typing import Any

from lib.print import NOT_RETURNED, pick

from pactman_nonprofit_check_plus import Nonprofit

SYNCED_FIELDS = [
    "organization_name", "organization_name_aka",
    "address_line1", "address_line2", "city", "state", "state_name", "zip",
    "subsection_description", "foundation_type_description",
    "bmf_status", "pub78_verified", "pactman_org_url", "organization_info_last_modified",
]


def merge(record: dict[str, Any], nonprofit: Nonprofit) -> dict[str, Any]:
    """A field is written only when the API returned a usable value.

    Null and absent both mean "no update available" — never "clear this". A sync
    that overwrites a good, human-entered address with null is a data-loss bug
    that looks like a feature until someone notices.
    """
    next_row = dict(record)

    for key in SYNCED_FIELDS:
        incoming = pick(nonprofit, key)

        if incoming is None or incoming is NOT_RETURNED:
            continue  # keep what the CRM holds

        next_row[key] = incoming

    return next_row


# EIN is the join key: stable, returned on every record, already in your CRM.
# Names change; EINs do not.
result = client.nonprofits.check_bulk(list(crm))
by_ein = {org["ein"]: org for org in result.organizations}

for ein, record in crm.items():
    nonprofit = by_ein.get(ein)

    if nonprofit is None:
        # A failed lookup is not new information. Leave the row untouched.
        crm[ein] = {**record, "last_sync_attempt_at": datetime.now(timezone.utc).isoformat()}
        continue

    crm[ein] = {
        **merge(record, nonprofit),
        # Without this, a row checked yesterday and one imported in 2019 look identical.
        "verified_at": datetime.now(timezone.utc).isoformat(),
        "verification_request_id": result.request_id,
        "verification_report_date": nonprofit.get("report_date"),
    }
```

#### EX-29 — Pre-disbursement recheck

Recheck immediately before a payout; a material change pauses it and both evidence sets are kept. [Full source](https://github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks/blob/master/python/examples/ex_29_pre_disbursement_recheck.py)

```python
from datetime import datetime, timezone
from typing import Any

from pactman_nonprofit_check_plus import PactmanError

# Changes that stop a disbursement outright at this organization.
BLOCKING = {
    "revocation_code", "revocation_date", "ofac_state",
    "bmf_status", "pub78_verified", "irs_bmf_pub78_conflict",
}


def recheck(payment: dict[str, Any], stored: dict[str, Any]) -> dict[str, Any]:
    try:
        # Retries stay on: a transient failure should be absorbed, not turned
        # into a false "changed" signal.
        result = client.nonprofits.check(payment["ein"], timeout=10.0)
    except PactmanError:
        # An unreachable API is not evidence that anything is fine.
        return {"decision": "hold", "reason": "recheck_failed"}

    if result.nonprofit is None:
        return {"decision": "hold", "reason": "no_record"}

    # collect_findings is your own projection of the response — store findings,
    # not a verdict: "approved" alone cannot be re-examined.
    current = collect_findings(result.nonprofit)
    changes = [key for key in current if current[key] != stored["findings"].get(key)]
    blocking = [key for key in changes if key in BLOCKING]

    # Both snapshots are kept. Neither overwrites the other.
    return {
        "decision": "hold" if blocking else "release",
        "prior_verification": stored,
        "current_verification": {
            "checked_at": datetime.now(timezone.utc).isoformat(),
            "request_id": result.request_id,
            "report_date": result.nonprofit.get("report_date"),
            "findings": current,
        },
        "changes": changes,
    }


# An organization approved at onboarding is not an organization approved today.
# Recheck as close to the money movement as your workflow allows.
```

#### EX-30 — Scheduled portfolio re-verification

Scheduled bulk re-verification with a diff against the last run and an explainable audit trail. [Full source](https://github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks/blob/master/python/examples/ex_30_portfolio_reverification.py)

```python
from datetime import datetime, timedelta, timezone

from pactman_nonprofit_check_plus import MAX_BULK_EINS

# Identify the rules that produced an outcome, so old entries stay readable.
POLICY_VERSION = "2026.02-portfolio-rev3"
RE_REVIEW_INTERVAL_DAYS = 90

eins = [entry["ein"] for entry in portfolio]
batches = [eins[index : index + MAX_BULK_EINS] for index in range(0, len(eins), MAX_BULK_EINS)]
records = {}

for batch in batches:
    result = client.nonprofits.check_bulk(batch)

    for org in result.organizations:
        records[org["ein"]] = {
            "org": org,
            "request_id": result.request_id,
            "status": result.status,
        }

    # An EIN that produced no record is unverified this cycle, not clean.
    for ein in result.not_found_eins:
        records[ein] = {"org": None, "request_id": result.request_id, "status": result.status}

for entry in portfolio:
    record = records.get(entry["ein"])
    findings = collect_findings(record["org"]) if record and record["org"] else None

    # A first run has nothing to compare against; say so rather than reporting
    # every field as "changed".
    is_baseline = entry["last_findings"] is None
    changes = (
        [] if is_baseline or findings is None else diff_findings(entry["last_findings"], findings)
    )

    audit_log.append(
        {
            "ein": entry["ein"],
            "checked_at": run_started_at.isoformat(),
            # Identifiers are stored; API keys never are.
            "request_id": record["request_id"] if record else None,
            "policy_version": POLICY_VERSION,
            "outcome": outcome,  # suspend | review | retain
            "changes": changes,
            "findings": findings,
            "next_review_due": (
                run_started_at + timedelta(days=RE_REVIEW_INTERVAL_DAYS)
            ).isoformat(),
        }
    )

    entry["last_findings"] = findings  # carry the snapshot forward for the next run

# What makes an audit trail useful is the evidence next to the outcome: when
# the check ran, which request it was, what each source said, and which policy
# version read them.
```

### One thing every example repeats

The SDK reports what the API returned. It produces no `approved`, `eligible` or `safe` verdict, and no boolean summarizing a source the API does not itself express as a boolean. Whether an organization qualifies for a donation, a grant, a match or a payout is a determination for your own legal, compliance and risk policy — which is why the routing logic in these examples lives in the example, never in the library.

## Development

```bash
python -m venv .venv && source .venv/bin/activate
pip install -e ".[dev]"

pytest                                       # unit tests
mypy                                         # type check, strict
ruff check .                                 # lint
python scripts/run_examples_against_mock.py  # every example, against the fixture API
```

## Support

- API documentation: <https://pactman.org/nonprofitcheckplus-api/docs>
- Pactman: <https://pactman.org>
- Issues: <https://github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks/issues>

## License

MIT — see [LICENSE](./LICENSE).
