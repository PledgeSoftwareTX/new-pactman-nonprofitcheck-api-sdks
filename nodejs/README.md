# @pactmandev/nonprofit-check-plus

Official Node.js SDK for the **Pactman Nonprofit Check Plus API**. Look up US nonprofits by EIN and read the IRS and OFAC findings behind the result.

- Typed models for every documented response field, with the raw payload always available
- Local EIN normalization and validation, so malformed input never costs a request
- A structured error taxonomy you branch on by type, never by parsing message strings
- Finite default timeout, cancellation, bounded retries with jittered backoff, and `Retry-After` support

> **Server-side only.** Your API key is a private credential. Do not construct this client in a browser, a mobile app, or anything else that ships to an end user.

---

## Contents

- [Requirements](#requirements)
- [Installation](#installation)
- [Configuring your API key](#configuring-your-api-key)
- [Quick start](#quick-start)
- [Environment and base URL](#environment-and-base-url)
- [Single check](#single-check)
- [Bulk check](#bulk-check)
- [Inspecting source-specific findings](#inspecting-source-specific-findings)
- [Response models and raw data](#response-models-and-raw-data)
- [EIN validation and normalization](#ein-validation-and-normalization)
- [Error handling](#error-handling)
- [Timeouts and cancellation](#timeouts-and-cancellation)
- [Retries](#retries)
- [Rate limits](#rate-limits)
- [Security](#security)
- [What this SDK does not tell you](#what-this-sdk-does-not-tell-you)
- [API reference](#api-reference)
- [Examples](#examples)
- [Support](#support)
- [License](#license)

---

## Requirements

- Node.js **18 or newer** (the SDK uses the built-in `fetch`; pass your own implementation via the `fetch` option if you need to)
- A Pactman API key with Nonprofit Check access

Ships both ESM and CommonJS builds with full TypeScript declarations.

## Installation

```bash
npm install @pactmandev/nonprofit-check-plus
```

```bash
pnpm add @pactmandev/nonprofit-check-plus
```

```bash
yarn add @pactmandev/nonprofit-check-plus
```

## Configuring your API key

Load the key from the environment or a secret manager. Never commit it, never inline it in source, and never expose it to a browser.

```bash
# .env — excluded from version control
PACTMAN_API_KEY=your_api_key_here
```

```ts
import { PactmanClient } from '@pactmandev/nonprofit-check-plus';

const client = new PactmanClient({
  apiKey: process.env.PACTMAN_API_KEY!,
});
```

The key is validated locally. A missing, empty, or whitespace-only key throws `PactmanConfigurationError` at construction, before any network call:

```ts
new PactmanClient({ apiKey: '' });
// PactmanConfigurationError: The Pactman API key is empty. Check that the
// environment variable holding it is set.
```

Every request carries the key as `Authorization: Bearer <key>`. It never appears in logs, error messages, `JSON.stringify(client)`, or `console.log(client)`.

## Quick start

```ts
import { PactmanClient } from '@pactmandev/nonprofit-check-plus';

const client = new PactmanClient({ apiKey: process.env.PACTMAN_API_KEY! });

const { nonprofit, checkCount } = await client.nonprofits.check('41-1787097');

console.log(nonprofit?.organization_name); // "EXAMPLE NONPROFIT"
console.log(nonprofit?.pub78_verified); // true
console.log(checkCount); // checks consumed by this request
```

CommonJS works the same way:

```js
const { PactmanClient } = require('@pactmandev/nonprofit-check-plus');
```

## Environment and base URL

Production is the default and the only named environment. Pactman's QA and sandbox hosts are internal and are not selectable from this package.

```ts
import { PactmanClient, PactmanEnvironment } from '@pactmandev/nonprofit-check-plus';

// These are equivalent.
new PactmanClient({ apiKey });
new PactmanClient({ apiKey, environment: PactmanEnvironment.Production });
```

For a local mock server, a proxy, or a host Pactman has given you directly, set `baseUrl`. It overrides `environment`, and is validated locally — a malformed URL throws `PactmanConfigurationError` before a request is attempted.

```ts
// Testing against a local mock.
const client = new PactmanClient({ apiKey, baseUrl: 'http://127.0.0.1:4010' });

client.baseUrl; // "http://127.0.0.1:4010"
client.environment; // null — an explicit host, not a named environment
```

Only the target host changes. Request and response semantics are identical.

## Single check

```ts
const result = await client.nonprofits.check('41-1787097');

result.nonprofit; // Nonprofit | null
result.checkCount; // checks consumed, from nonprofit_check_count
result.timeTakenMs; // server-side processing time
result.status; // HTTP status
result.requestId; // correlation ID, when the server sends one
result.raw; // the unmodified response envelope
```

`'41-1787097'` and `'411787097'` are the same request — the EIN is normalized before the URL is built.

## Bulk check

```ts
const result = await client.nonprofits.checkBulk(['41-1787097', '996589560', '996202676']);

for (const org of result.organizations) {
  console.log(org.ein, org.organization_name);
}

// EINs with no record are not an error — they come back on a 200 response.
console.log(result.notFoundEins); // ["996202676"]
console.log(result.checkCount);
```

Behaviour worth knowing:

|                 |                                                                                             |
| --------------- | ------------------------------------------------------------------------------------------- |
| **Batch limit** | 50 EINs per request, enforced locally before sending. Exported as `MAX_BULK_EINS`.          |
| **Chunking**    | None. Larger inputs throw rather than silently splitting into several billable requests.    |
| **Order**       | Preserved exactly as supplied.                                                              |
| **Duplicates**  | Kept by default, because each one consumes quota. Pass `{ dedupe: true }` to collapse them. |
| **Empty input** | Throws `PactmanValidationError` locally.                                                    |
| **One bad EIN** | The whole batch is rejected locally, identifying the failing index. Nothing is sent.        |

```ts
// Opt in to deduplication.
await client.nonprofits.checkBulk(eins, { dedupe: true });
```

## Inspecting source-specific findings

The API returns source fields flat on the organization (`pub78_*`, `bmf_*`, `ofac_*`, and the revocation fields). Read them directly, or use the grouped accessors — which copy fields 1:1 and derive nothing.

```ts
import { getBmf, getOfac, getPub78, getAroe } from '@pactmandev/nonprofit-check-plus';

const { nonprofit } = await client.nonprofits.check('41-1787097');
if (!nonprofit) return;

// IRS Publication 78
const pub78 = getPub78(nonprofit);
if (pub78 === null) {
  console.log('Publication 78 data was not returned for this organization.');
} else {
  console.log(pub78.verified); // true | false | null
  console.log(pub78.most_recent); // date of the Pub 78 record
}

// IRS Business Master File
const bmf = getBmf(nonprofit);
console.log(bmf?.status, bmf?.subsection_description);

// IRS Automatic Revocation of Exemption
const aroe = getAroe(nonprofit);
console.log(aroe?.revocation_code, aroe?.revocation_date, aroe?.reinstatement_date);

// OFAC Specially Designated Nationals
const ofac = getOfac(nonprofit);
console.log(ofac?.status); // a sentence describing the finding
```

Each accessor returns `null` only when the API returned **no data at all** for that source. That keeps _"the source was not returned"_ distinct from an explicit negative such as `pub78_verified: false`.

**On OFAC:** the API returns `ofac_status` as prose, not a boolean. This SDK deliberately does not expose a `hasOfacMatch` flag, because deriving one would mean pattern-matching English that could be reworded at any time. Read the status, or route it to a reviewer.

## Response models and raw data

Field names mirror the wire format exactly, so the API reference and your code use the same names — there is no rename table to keep in sync.

Unknown fields never break deserialization. Anything the API adds in a future version is readable through the same object and through `raw`:

```ts
const result = await client.nonprofits.check('411787097');

result.nonprofit?.['some_future_field']; // readable without an SDK upgrade
result.raw; // the complete, unmodified envelope
```

`null` and `false` are preserved as distinct values wherever the API distinguishes them.

## EIN validation and normalization

```ts
import { isValidEin, normalizeEin, normalizeEins } from '@pactmandev/nonprofit-check-plus';

normalizeEin('41-1787097'); // "411787097"
normalizeEin('411787097'); // "411787097"
isValidEin('4117870'); // false
```

Accepted: nine digits, with or without the conventional hyphen after the two-digit prefix, ignoring surrounding whitespace. Rejected: letters, other punctuation, wrong digit counts, empty and null values. No IRS prefix rules are applied.

Bulk validation reports every failure at once, by index:

```ts
try {
  await client.nonprofits.checkBulk(['411787097', 'nope', '1234']);
} catch (error) {
  if (error instanceof PactmanValidationError) {
    for (const issue of error.issues) {
      console.error(issue.index, issue.value, issue.message);
    }
  }
}
```

> Formatting validation confirms only that a value is shaped like an EIN. It says nothing about tax-exempt status, identity, eligibility, or good standing.

## Error handling

Every failure is a `PactmanError` with a stable `category` and an `origin` of `'local'` or `'api'`. Branch on the class or the category — never on message text.

```ts
import {
  PactmanApiError,
  PactmanAuthenticationError,
  PactmanRateLimitError,
  PactmanTimeoutError,
  PactmanValidationError,
} from '@pactmandev/nonprofit-check-plus';

try {
  await client.nonprofits.check(ein);
} catch (error) {
  if (error instanceof PactmanValidationError) {
    // Bad input. Nothing was sent.
  } else if (error instanceof PactmanAuthenticationError) {
    // The key was rejected.
  } else if (error instanceof PactmanRateLimitError) {
    console.log(error.retryAfterSeconds);
  } else if (error instanceof PactmanTimeoutError) {
    console.log(error.timeoutMs);
  } else if (error instanceof PactmanApiError) {
    console.log(error.status, error.requestId, error.apiErrors);
  }
}
```

| Class                        | Category         | Origin | Raised for                          |
| ---------------------------- | ---------------- | ------ | ----------------------------------- |
| `PactmanConfigurationError`  | `configuration`  | local  | Unusable client options             |
| `PactmanValidationError`     | `validation`     | local  | Input rejected before sending       |
| `PactmanBadRequestError`     | `bad_request`    | api    | HTTP 400                            |
| `PactmanAuthenticationError` | `authentication` | api    | HTTP 401                            |
| `PactmanAuthorizationError`  | `authorization`  | api    | HTTP 403                            |
| `PactmanNotFoundError`       | `not_found`      | api    | HTTP 404                            |
| `PactmanRateLimitError`      | `rate_limit`     | api    | HTTP 429                            |
| `PactmanServerError`         | `server`         | api    | HTTP 5xx                            |
| `PactmanApiError`            | `api`            | api    | Any other unexpected response       |
| `PactmanTimeoutError`        | `timeout`        | local  | Exceeded the configured timeout     |
| `PactmanNetworkError`        | `network`        | local  | No response, or caller cancellation |

API errors carry `status`, `apiCode`, `apiMessage`, `apiErrors`, `requestId`, `retryAfterSeconds`, `attempts`, and `raw`. When a body cannot be deserialized, the metadata is still preserved and `raw` holds what the server actually sent.

## Timeouts and cancellation

The default timeout is **30 seconds** per attempt, exported as `DEFAULT_TIMEOUT_MS`. It is always finite — there is no way to disable it.

```ts
const client = new PactmanClient({ apiKey, timeoutMs: 10_000 });

// Or per request.
await client.nonprofits.check(ein, { timeoutMs: 5_000 });
```

Pass an `AbortSignal` to cancel. Cancellation stops the in-flight request _and_ any planned retries.

```ts
const controller = new AbortController();
setTimeout(() => controller.abort(), 2_000);

await client.nonprofits.check(ein, { signal: controller.signal });
```

## Retries

Enabled by default: up to **2 retries** (3 attempts total), exponential backoff from 500ms with full jitter, capped at 8 seconds per delay.

```ts
const client = new PactmanClient({
  apiKey,
  retry: {
    maxRetries: 3,
    initialDelayMs: 500,
    maxDelayMs: 8_000,
    backoffFactor: 2,
    jitter: true,
    retryableStatuses: [429, 500, 502, 503, 504],
    respectRetryAfter: true,
  },
});

// Disable entirely.
new PactmanClient({ apiKey, retry: false });

// Or override per request.
await client.nonprofits.check(ein, { retry: { maxRetries: 0 } });
```

Retried: 429, 500, 502, 503, 504, and transient network failures. **Never** retried: 400, 401, 403, 404, and local validation errors — regardless of `retryableStatuses`. A valid `Retry-After` always takes precedence over computed backoff.

## Rate limits

The API returns HTTP 429 when you exceed your limit. The SDK maps that to `PactmanRateLimitError` and exposes `retryAfterSeconds`.

```ts
try {
  await client.nonprofits.check(ein);
} catch (error) {
  if (error instanceof PactmanRateLimitError) {
    console.log(`Retry in ${error.retryAfterSeconds ?? 'unknown'} seconds`);
  }
}
```

With retries enabled, a 429 is retried automatically after the server's `Retry-After`, falling back to backoff when none is sent.

An optional client-side ceiling is available and off by default:

```ts
const client = new PactmanClient({ apiKey, maxRequestsPerSecond: 3 });
```

Server-provided limits are authoritative and may vary by account and endpoint; treat this as a courtesy throttle, not a guarantee. For bulk workloads, prefer the bulk endpoint over concurrent single checks, and keep your own concurrency bounded — the SDK does not queue on your behalf.

## Security

- Load the key from an environment variable or secret manager. Never commit it.
- **Server-side only.** Authenticated calls from a browser expose the key to anyone who opens devtools.
- The key is redacted from every diagnostic surface: error messages, `error.toJSON()`, `JSON.stringify(client)`, `console.log(client)`, and `util.inspect`.
- Rotate the key if it is ever printed, logged, or committed.
- Nonprofit records may be subject to your own retention and privacy obligations. Storing responses is your call, not the SDK's.

## What this SDK does not tell you

The SDK exposes what the API returns and nothing more. It deliberately provides **no** composite `approved`, `eligible`, or `safe` verdict, and no boolean summarizing a source that the API does not itself express as a boolean.

A successful check is data, not a decision. Whether an organization qualifies for a grant, a donation, a match, or a partnership is a determination for your own legal, compliance, grantmaking, and risk policy.

## API reference

**Client** — `new PactmanClient(options)`

| Option                 | Type                     | Default        |                                                 |
| ---------------------- | ------------------------ | -------------- | ----------------------------------------------- |
| `apiKey`               | `string`                 | —              | **Required.**                                   |
| `environment`          | `PactmanEnvironment`     | `'production'` | Named environment.                              |
| `baseUrl`              | `string`                 | —              | Explicit host; overrides `environment`.         |
| `timeoutMs`            | `number`                 | `30000`        | Per-attempt timeout.                            |
| `retry`                | `RetryOptions \| false`  | 2 retries      | Retry policy.                                   |
| `maxRequestsPerSecond` | `number`                 | off            | Optional client-side throttle.                  |
| `defaultHeaders`       | `Record<string, string>` | `{}`           | Extra headers; cannot override `Authorization`. |
| `fetch`                | `FetchLike`              | global `fetch` | Custom HTTP implementation.                     |

Properties: `client.nonprofits`, `client.baseUrl`, `client.environment`, `client.timeoutMs`.

**Methods**

- `client.nonprofits.check(ein, options?)` → `Promise<SingleCheckResult>`
- `client.nonprofits.checkBulk(eins, options?)` → `Promise<BulkCheckResult>`

Both accept `{ timeoutMs, retry, signal, headers }`; `checkBulk` also accepts `{ dedupe }`.

**Helpers** — `normalizeEin`, `normalizeEins`, `isValidEin`, `getPub78`, `getBmf`, `getAroe`, `getOfac`, `supportedEnvironments`, `baseUrlForEnvironment`, `isPactmanError`

**Constants** — `MAX_BULK_EINS`, `DEFAULT_TIMEOUT_MS`, `DEFAULT_ENVIRONMENT`, `EIN_LENGTH`, `VERSION`

**Types** — `Nonprofit`, `OrganizationType`, `SingleCheckResult`, `BulkCheckResult`, `ApiEnvelope`, `ApiErrorDetail`, `PactmanClientOptions`, `RetryOptions`, `RequestOptions`, `Pub78Source`, `BmfSource`, `AroeSource`, `OfacSource`

All public members carry TSDoc, so editor autocomplete and hover documentation work without leaving your code.

## Examples

Runnable examples live in [`examples/`](./examples). They read `PACTMAN_API_KEY` from the environment and contain no credentials.

```bash
npm run build
PACTMAN_API_KEY=your_key npm run example:quickstart
PACTMAN_API_KEY=your_key npm run example:bulk
PACTMAN_API_KEY=your_key npm run example:errors
```

CI runs all three against a local mock server on every push:

```bash
npm run examples:smoke
```

## Support

- API documentation: <https://pactman.org/nonprofitcheckplus-api/docs>
- Pactman: <https://pactman.org>
- Issues: <https://github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks/issues>

## License

MIT — see [LICENSE](./LICENSE).
