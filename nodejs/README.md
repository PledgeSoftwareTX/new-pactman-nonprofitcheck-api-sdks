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
- [Usage and billing cycle](#usage-and-billing-cycle)
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
  - [Getting started](#getting-started) — EX-01 to EX-03
  - [Comparing and validating against the record](#comparing-and-validating-against-the-record) — EX-04, EX-05
  - [Reading the sources](#reading-the-sources) — EX-06 to EX-14
  - [Errors and edge cases](#errors-and-edge-cases) — EX-15, EX-16, EX-22 to EX-25
  - [Bulk](#bulk) — EX-17 to EX-21
  - [End-to-end workflows](#end-to-end-workflows) — EX-26 to EX-30
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
console.log(checkCount); // checks used so far this billing cycle
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
result.checkCount; // nonprofit_check_count — see "Usage and billing cycle" below
result.timeTakenMs; // server-side processing time
result.status; // HTTP status
result.requestId; // correlation ID, when the server sends one
result.raw; // the unmodified response envelope
```

`'41-1787097'` and `'411787097'` are the same request — the EIN is normalized before the URL is built.

## Bulk check

```ts
const result = await client.nonprofits.checkBulk(['41-1787097', '996589560', '999999999']);

for (const org of result.organizations) {
  console.log(org.ein, org.organization_name);
}

// EINs with no record are not an error — they come back on a 200 response.
console.log(result.notFoundEins); // ["999999999"]
console.log(result.checkCount);
```

Behaviour worth knowing:

|                    |                                                                                                                               |
| ------------------ | ----------------------------------------------------------------------------------------------------------------------------- |
| **Batch limit**    | 50 EINs per request, enforced locally before sending. Exported as `MAX_BULK_EINS`.                                            |
| **Chunking**       | None. Larger inputs throw rather than silently splitting into several billable requests.                                      |
| **Request order**  | Your EINs are sent exactly as supplied. The SDK never reorders them.                                                          |
| **Response order** | Not guaranteed to match. The API matches by set membership — index `organizations` by `ein`, never pair them positionally.    |
| **Duplicates**     | Sent as supplied, because each one is billable. A repeated EIN still returns one record. Pass `{ dedupe: true }` to collapse. |
| **Empty input**    | Throws `PactmanValidationError` locally.                                                                                      |
| **One bad EIN**    | The whole batch is rejected locally, identifying the failing index. Nothing is sent.                                          |
| **No matches**     | A batch where nothing matched is an error; a batch where some matched is a 200 with the rest in `notFoundEins`.               |

```ts
// Opt in to deduplication.
await client.nonprofits.checkBulk(eins, { dedupe: true });

// Index by EIN — the pairing that always holds.
const byEin = new Map(result.organizations.map(org => [org.ein, org]));
```

## Usage and billing cycle

`nonprofit_check_count`, surfaced as `result.checkCount`, is the number of checks your account has consumed **so far in the current billing cycle**, including the request that returned it. It resets when a new cycle starts.

It is not the size of the request you just made. A bulk call for five EINs does not return `5`.

```ts
const before = await client.nonprofits.check(ein);
const after = await client.nonprofits.checkBulk(eins);

after.checkCount; // cycle total, e.g. 1_284
after.checkCount - before.checkCount; // what these requests actually consumed
```

EINs with no matching record are not billed, so a delta can be smaller than the batch you sent. Read the number the API reports rather than reconstructing usage from your input.

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

Thirty numbered, runnable examples cover secure setup, every source on the response, each error and edge case, bulk semantics, and five end-to-end workflows.

Each one is reproduced below, condensed to the point it makes. Every snippet assumes the imports and a `client` from [Quick start](#quick-start), and omits the output formatting the runnable file uses. The full sources live in [`examples/`](https://github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks/tree/master/nodejs/examples) in the repository — they read `PACTMAN_API_KEY` from the environment and contain no credentials.

```bash
git clone https://github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks.git
cd new-pactman-nonprofitcheck-api-sdks/nodejs && npm install && npm run build

PACTMAN_API_KEY=your_key node examples/ex-01-secure-client-init.mjs
PACTMAN_API_KEY=your_key node examples/ex-03-identity-lookup.mjs 41-1787097
```

Examples for scenarios a live API will not produce on request — a revoked exemption, an OFAC match, an HTTP 429, a response carrying a field newer than this SDK — run against a bundled fixture server they start themselves. CI runs all thirty on every push:

```bash
npm run examples:smoke                     # pass/fail
EXAMPLES_VERBOSE=1 npm run examples:smoke  # with output
npm run examples:smoke -- ex-22 ex-23      # a subset
```

Three shorter files sit alongside the numbered set for a first read: [`quickstart.mjs`](https://github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks/blob/master/nodejs/examples/quickstart.mjs) (`npm run example:quickstart`), [`bulk.mjs`](https://github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks/blob/master/nodejs/examples/bulk.mjs) (`npm run example:bulk`) and [`error-handling.mjs`](https://github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks/blob/master/nodejs/examples/error-handling.mjs) (`npm run example:errors`).

### Getting started

#### EX-01 — Secure client initialization

Load the key from the environment, pick an environment, set a finite timeout, build one reusable client — and prove the key reaches no log, no exception, no debug output. [Full source](https://github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks/blob/master/nodejs/examples/ex-01-secure-client-init.mjs)

```js
import { inspect } from 'node:util';
import { PactmanClient, PactmanEnvironment } from '@pactmandev/nonprofit-check-plus';

const apiKey = process.env.PACTMAN_API_KEY;

if (!apiKey) {
  throw new Error('Set PACTMAN_API_KEY. Load it from your secret manager or an ignored .env.');
}

// One client, built once, reused for the life of the process. Constructing a
// client per request throws away connection reuse and any throttle state.
const client = new PactmanClient({
  apiKey,
  environment: PactmanEnvironment.Production, // the default; naming it is explicit at review time
  timeoutMs: 10_000,                          // the 30s default is often too long for a caller-facing service
});

// Every diagnostic surface, checked against the real key. None of them hold it.
const surfaces = [inspect(client), JSON.stringify(client), client.toString()];

surfaces.some(text => text.includes(apiKey)); // false
```

#### EX-02 — EIN normalization

A hyphenated, whitespace-padded EIN normalized to nine digits before the request, with the original kept for diagnostics. [Full source](https://github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks/blob/master/nodejs/examples/ex-02-ein-normalization.mjs)

```js
import { isValidEin, normalizeEin } from '@pactmandev/nonprofit-check-plus';

const submitted = '  41-1787097  '; // what an onboarding form actually sends

isValidEin(submitted); // true
normalizeEin(submitted); // "411787097"

// Store the normalized form as your key — it is what the API echoes back — and
// keep the raw input beside it so support can see what the applicant typed.
const applicant = { einAsSubmitted: submitted, ein: normalizeEin(submitted) };

// check() normalizes internally too, so either form is the same request.
const { nonprofit } = await client.nonprofits.check(applicant.einAsSubmitted);

nonprofit?.ein; // "411787097"
```

#### EX-03 — Identity lookup

EIN, name, AKA and Pactman profile URL, plus the raw envelope alongside the typed model. [Full source](https://github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks/blob/master/nodejs/examples/ex-03-identity-lookup.mjs)

```js
const result = await client.nonprofits.check('41-1787097');

if (result.nonprofit) {
  const { nonprofit } = result;

  nonprofit.ein;
  nonprofit.organization_name;
  nonprofit.organization_name_aka; // frequently null: "none on file", not "none exists"
  nonprofit.pactman_org_url;

  // Response metadata.
  result.status;
  result.requestId;
  result.timeTakenMs;
  result.checkCount;

  // The typed model is a view over the envelope, not a replacement for it.
  result.raw.code;
  result.raw.message;
  result.raw.data?.ein;
}
```

### Comparing and validating against the record

#### EX-04 — Applicant name comparison

Compare a submitted name with `organization_name` and `organization_name_aka` without treating punctuation or abbreviation differences as fraud. [Full source](https://github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks/blob/master/nodejs/examples/ex-04-name-comparison.mjs)

```js
// The SDK deliberately has no namesMatch(). What counts as a match is policy,
// so the comparison lives in customer code.
const normalize = name =>
  String(name)
    .toUpperCase()
    .replace(/\b(INC|INCORPORATED|CORP|CO|LLC|LTD|THE)\b\.?/g, '')
    .replace(/[^A-Z0-9 ]/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();

const { nonprofit } = await client.nonprofits.check(applicant.ein);

const candidates = [nonprofit?.organization_name, nonprofit?.organization_name_aka].filter(
  name => typeof name === 'string',
);

const outcome =
  candidates.length === 0
    ? 'not_returned' // no name came back — nothing was compared
    : candidates.some(name => normalize(name) === normalize(applicant.legalName))
      ? 'agreement'
      : 'mismatch';

// A mismatch is a reason to look, not a finding: organizations rebrand, file
// under a parent, and appear in IRS data under a name no donor would recognize.
const routed = outcome === 'agreement' ? 'continue' : 'manual_review';
```

#### EX-05 — Validating the returned address

Ask whether the address the API returned is well-formed and self-consistent, before acting on it. [Full source](https://github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks/blob/master/nodejs/examples/ex-05-address-validation.mjs)

```js
const { nonprofit } = await client.nonprofits.check(ein);

// `state` and `state_name` are two fields for one fact, and the ZIP encodes the
// state a third time. A record can be complete and still contradict itself.
const state = nonprofit?.state?.trim().toUpperCase() ?? null;
const zipDigits = String(nonprofit?.zip ?? '').replace(/\D/g, '');

const missing = ['address_line1', 'city', 'state', 'zip'].filter(
  component => nonprofit?.[component] == null || String(nonprofit[component]).trim() === '',
);

const failures = [
  US_STATES.has(state) ? null : 'state is not a USPS code',
  // A check that cannot run reports nothing, never a failure: an incomplete
  // lookup table must not manufacture a finding about somebody's address.
  US_STATES.get(state) === nonprofit?.state_name ? null : 'state_name disagrees with state',
  [5, 9].includes(zipDigits.length) ? null : 'zip is not 5 or 9 digits',
  statesForZip(zipDigits)?.has(state) === false ? 'zip belongs to another state' : null,
].filter(Boolean);

// Three verdicts, and the middle one is the point. Absence is not validity.
const verdict = failures.length > 0 ? 'inconsistent' : missing.length > 0 ? 'incomplete' : 'usable';
const routed = verdict === 'usable' ? 'continue' : 'manual_review';

// Well-formed is not deliverable. USPS, Lob, Smarty and Google Address
// Validation answer that one, over the network, with a second credential.
```

### Reading the sources

#### EX-06 — IRS Business Master File status

Every IRS Business Master File field on the response — status, identity, subsection, exemption, ruling, foundation. [Full source](https://github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks/blob/master/nodejs/examples/ex-06-bmf-status.mjs)

```js
import { getBmf } from '@pactmandev/nonprofit-check-plus';

const bmf = getBmf(nonprofit);

if (bmf === null) {
  // Not "not in the BMF" — the API returned no BMF fields at all. That is an
  // absence of evidence, not a negative finding. Route it to review.
} else {
  bmf.status; // one source's answer to one question — there is no isExempt here
  bmf.exempt_status_code;
  bmf.deductability_text;
  bmf.most_recent;

  bmf.organization_name, bmf.ein, bmf.street_address, bmf.city, bmf.state, bmf.church_message;
  bmf.subsection, bmf.subsection_description;
  bmf.ruling_month, bmf.ruling_year, bmf.group_exemption;
  bmf.foundation_code, bmf.foundation_code_description;
  bmf.foundation_type_code, bmf.foundation_type_description, bmf.foundation_509a_status;
  bmf.filing_req_code, bmf.pf_filing_req_cd;
}

// Reading the BMF in isolation is how a revoked or sanctioned organization
// passes a check — see EX-08 and EX-10.
```

#### EX-07 — Publication 78 and deductibility

Publication 78 verification and deductibility entries, with a donation policy applied in customer code. [Full source](https://github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks/blob/master/nodejs/examples/ex-07-pub78-deductibility.mjs)

```js
import { getPub78 } from '@pactmandev/nonprofit-check-plus';

const pub78 = getPub78(nonprofit);

pub78?.verified; // true | false | null
pub78?.indicator;
pub78?.church_message;
pub78?.most_recent;
pub78?.source_org_type_1; // …_2, …_3

for (const entry of pub78?.organization_types ?? []) {
  entry.deductibility_status_description;
  entry.deductibility_limitation;
  entry.organization_type;
}

// Your policy, expressed against the source data. Change the predicate, not the
// SDK — nothing here is a verdict the API handed down.
const ACCEPTED_LIMITATIONS = ['50%', '60%'];

const limitations = (pub78?.organization_types ?? [])
  .map(entry => entry.deductibility_limitation)
  .filter(value => value !== null && value !== undefined);

const eligibleUnderThisPolicy =
  pub78?.verified === true && limitations.some(value => ACCEPTED_LIMITATIONS.includes(value));
```

#### EX-08 — Automatic revocation detected

An organization in the IRS Automatic Revocation data, flagged and recorded with its source fields. [Full source](https://github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks/blob/master/nodejs/examples/ex-08-automatic-revocation.mjs)

```js
import { getAroe } from '@pactmandev/nonprofit-check-plus';

const aroe = getAroe(nonprofit);
const revoked = Boolean(aroe?.revocation_code || aroe?.revocation_date);

// The application's policy, in one place, expressed against source fields.
const action = !revoked ? 'continue' : aroe.reinstatement_date ? 'manual_review' : 'block';

// What you keep is what you can explain later. Store the source fields, the
// request identifier and the time you looked — not just the verdict.
const auditRecord = {
  ein: nonprofit.ein,
  checkedAt: new Date().toISOString(),
  requestId: result.requestId,
  action,
  sourceFindings: {
    revocation_code: nonprofit.revocation_code,
    revocation_date: nonprofit.revocation_date,
    reinstatement_date: nonprofit.reinstatement_date,
    aroe_list_published_date: nonprofit.aroe_list_published_date,
    bmf_status: nonprofit.bmf_status, // revocation shows up in the other sources too
    pub78_verified: nonprofit.pub78_verified,
  },
};
```

#### EX-09 — Revocation with reinstatement

Revocation and reinstatement dates kept separate, and the questions reinstatement does not answer. [Full source](https://github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks/blob/master/nodejs/examples/ex-09-revocation-reinstatement.mjs)

```js
const aroe = getAroe(nonprofit);

// The API formats dates as `M/DD/YYYY h:mm:ss AM`. Parse; never reformat in place.
const parse = value => {
  const parsed = value ? new Date(value) : null;
  return parsed && !Number.isNaN(parsed.getTime()) ? parsed : null;
};

const revokedAt = parse(aroe?.revocation_date);
const reinstatedAt = parse(aroe?.reinstatement_date);

// Nothing collapses the two into a "currently revoked" boolean — that boolean
// would lose the interval, and donations dated inside it may need handling.
if (revokedAt && reinstatedAt) {
  const lapsedDays = Math.round((reinstatedAt.getTime() - revokedAt.getTime()) / 86_400_000);
}

// Reinstatement resolves one question, not every question: was it retroactive?
// Do gifts made during the lapse need re-characterizing? Does your grant
// agreement require continuous exemption? This record still goes to review.
```

#### EX-10 — OFAC screening result

Four distinct OFAC outcomes — no match, match, null, and not screened at all. [Full source](https://github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks/blob/master/nodejs/examples/ex-10-ofac-screening.mjs)

```js
import { getOfac } from '@pactmandev/nonprofit-check-plus';

// The SDK exposes no hasOfacMatch boolean: deriving one means pattern-matching
// English the source can reword at any time. The one textual test below
// escalates and never clears — anything unrecognized falls through to review.
function classifyOfac(nonprofit) {
  const ofac = getOfac(nonprofit);

  if (ofac === null) return 'unavailable'; // no OFAC field at all; nothing was screened
  if (ofac.status === null || ofac.status === undefined) return 'null';
  if (/UID:/i.test(ofac.status)) return 'match';
  if (/NOT included/i.test(ofac.status)) return 'no_match';

  return 'needs_review';
}

// Four states, four destinations. None of them is "approve automatically".
const ROUTING = {
  no_match: 'continue — screened against the SDN list with no match',
  match: 'block and escalate to compliance',
  null: 'hold — the field was returned empty; treat as unscreened, not as cleared',
  unavailable: 'hold — no OFAC data was returned',
  needs_review: 'hold — the status text was not recognized by this application',
};

ROUTING[classifyOfac(nonprofit)];
```

#### EX-11 — Cross-source conflict

`irs_bmf_pub78_conflict` handled by recording both sources, not by picking one. [Full source](https://github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks/blob/master/nodejs/examples/ex-11-source-conflict.mjs)

```js
const bmf = getBmf(nonprofit);
const pub78 = getPub78(nonprofit);
const findings = [];

// The flag the API sets is authoritative; the comparisons only explain it.
if (nonprofit.irs_bmf_pub78_conflict === true) {
  findings.push('The API flagged a BMF / Publication 78 disagreement.');
}

if (bmf?.status === true && pub78?.verified === false) {
  findings.push('The BMF lists the organization as exempt; Publication 78 does not list it.');
}

if (bmf?.status === false && pub78?.verified === true) {
  findings.push('Publication 78 lists the organization; the BMF does not show it as exempt.');
}

// Both sides are kept, side by side, for the reviewer. Silently preferring one
// source means being wrong for some organization with the evidence destroyed.
const reviewRecord =
  findings.length > 0
    ? { ein: nonprofit.ein, requestId: result.requestId, findings, sources: { bmf, pub78 } }
    : null;
```

#### EX-12 — Organization type and foundation classification

Organization types, foundation and subsection classification for a grantmaker or DAF display. [Full source](https://github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks/blob/master/nodejs/examples/ex-12-foundation-classification.mjs)

```js
const bmf = getBmf(nonprofit);
const pub78 = getPub78(nonprofit);

// What a grant officer sees. Every value is copied, none is computed — and the
// descriptions come from the API's own *_description fields, which stay correct
// when the source changes. A lookup table in your repository does not.
const classificationPanel = {
  subsection: bmf?.subsection_description,
  foundationCode: bmf?.foundation_code_description,
  foundationType: bmf?.foundation_type_description,
  status509a: bmf?.foundation_509a_status,
  deductibility: bmf?.deductability_text,
  entries: pub78?.organization_types,
};

// A private foundation grantee is not disqualified — it is routed differently,
// because expenditure responsibility and the deductibility limit both change.
const isPrivateFoundation = bmf?.foundation_type_code === 'pf' || bmf?.pf_filing_req_cd === '1';
```

#### EX-13 — Filing and exemption metadata

Filing and exemption codes preserved exactly, or mapped through documented tables with an unknown-value fallback. [Full source](https://github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks/blob/master/nodejs/examples/ex-13-filing-exemption-metadata.mjs)

```js
const FILING_REQUIREMENTS = { '01': '990 (all other) or 990-EZ return', '02': '990 - Required to file Form 990-N' };

// A documented table with an explicit unknown fallback. A value the IRS adds
// reads as "unrecognized" — never as undefined, and never as the wrong label.
function describe(table, code) {
  if (code === null || code === undefined) return { code, known: false, display: '<not returned>' };

  const description = table[code];

  return { code, known: description !== undefined, display: description ?? `unrecognized code "${code}"` };
}

const bmf = getBmf(nonprofit);

describe(FILING_REQUIREMENTS, bmf?.filing_req_code);

// Codes the API already describes for you: read its description, do not shadow
// it with a local table that will drift.
bmf?.subsection, bmf?.subsection_description;
bmf?.foundation_code, bmf?.foundation_code_description;
bmf?.ruling_month, bmf?.ruling_year; // raw values, preserved exactly, null included

// Never coerce an unrecognized code to a default. "Unknown" is a real state,
// and it usually means review rather than approval.
```

#### EX-14 — Data freshness and report metadata

Source timestamps, report date and request timing, feeding an application-owned re-review rule. [Full source](https://github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks/blob/master/nodejs/examples/ex-14-data-freshness.mjs)

```js
// Your rule. The SDK has no isStale and no default threshold, because 90 days
// is prudent for one workflow and reckless for another.
const RE_REVIEW_AFTER_DAYS = 90;

const timestamps = {
  organization_info_last_modified: nonprofit.organization_info_last_modified,
  report_date: nonprofit.report_date, // when this response was generated
  most_recent_bmf: nonprofit.most_recent_bmf, // when each list was last refreshed
  most_recent_pub78: nonprofit.most_recent_pub78,
  ofac_list_published_date: nonprofit.ofac_list_published_date,
  aroe_list_published_date: nonprofit.aroe_list_published_date,
};

const ages = Object.entries(timestamps).map(([name, value]) => ({
  name,
  ageDays: value ? Math.round((Date.now() - new Date(value).getTime()) / 86_400_000) : null,
}));

const undated = ages.filter(entry => entry.ageDays === null);
const oldest = Math.max(...ages.map(entry => entry.ageDays ?? 0));

// The oldest source governs, and an undated source is not a fresh one.
const needsReReview = oldest > RE_REVIEW_AFTER_DAYS || undated.length > 0;

// Store the timestamps with the verification record, not just the outcome. "We
// checked and it was fine" is not an answer six months later; "we checked on
// this date against BMF data published on that date" is.
const evidence = { ein: nonprofit.ein, checkedAt: new Date().toISOString(), requestId: result.requestId, ...timestamps };
```

### Errors and edge cases

#### EX-15 — Malformed EIN rejected locally

Every malformed shape rejected locally, with an instrumented `fetch` proving no request was sent. [Full source](https://github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks/blob/master/nodejs/examples/ex-15-malformed-ein.mjs)

```js
import { PactmanClient, PactmanValidationError } from '@pactmandev/nonprofit-check-plus';

// A counting wrapper around the runtime's fetch, to prove the claim rather than
// assert it. If any call below reaches the network, this number moves.
let requestsSent = 0;

const client = new PactmanClient({
  apiKey: process.env.PACTMAN_API_KEY,
  fetch: (input, init) => {
    requestsSent += 1;
    return globalThis.fetch(input, init);
  },
});

const bad = ['41178709', '4117870977', '41-178709A', '', '   ', null, 411787097, '41.1787097', '411-787097'];

for (const value of bad) {
  try {
    await client.nonprofits.check(value);
  } catch (error) {
    if (!(error instanceof PactmanValidationError)) throw error;

    error.origin; // "local"
    error.issues[0]; // { index, value, message } — enough to highlight the form field
  }
}

// Bulk reports every failure at once, by index.
await client.nonprofits.checkBulk(['411787097', 'nope', '996589560']).catch(error => error.issues);

requestsSent; // 0 — bad input costs no quota, no latency, no rate-limit budget
```

#### EX-16 — EIN not found

A well-formed EIN with no record: `PactmanNotFoundError`, sanitized diagnostics, and why bulk behaves differently. [Full source](https://github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks/blob/master/nodejs/examples/ex-16-not-found.mjs)

```js
import { PactmanApiError, PactmanNotFoundError, isPactmanError } from '@pactmandev/nonprofit-check-plus';

try {
  await client.nonprofits.check('999999999');
} catch (error) {
  if (!(error instanceof PactmanNotFoundError)) throw error;

  // Stable identity: class, category, origin. Never parse `message`.
  error.category; // "not_found"
  error.origin; // "api"
  error instanceof PactmanApiError; // true — catch the specific case or the general one
  isPactmanError(error); // true

  // The envelope's own detail survives onto the error.
  error.status, error.apiCode, error.apiMessage, error.requestId, error.apiErrors;
  error.attempts; // 1 — not-found is not a transient failure, so it is never retried

  JSON.stringify(error); // sanitized: safe to log, safe to attach to a support ticket
}

// The bulk endpoint behaves differently: unmatched EINs come back on a 200.
const mixed = await client.nonprofits.checkBulk(['411787097', '999999999']);

mixed.status; // 200
mixed.notFoundEins; // ["999999999"]

// Only a request where nothing at all matched is a 404.
```

#### EX-22 — Rate limits and `Retry-After`

HTTP 429, `Retry-After`, bounded retries, a client-side rate ceiling and a bounded concurrency pool. [Full source](https://github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks/blob/master/nodejs/examples/ex-22-rate-limit.mjs)

```js
import { PactmanClient, PactmanRateLimitError } from '@pactmandev/nonprofit-check-plus';

// 1. Retries off, so the 429 reaches the caller untouched.
try {
  await client.nonprofits.check(ein, { retry: false });
} catch (error) {
  if (!(error instanceof PactmanRateLimitError)) throw error;

  error.status; // 429
  error.retryAfterSeconds; // the server's number, when it sent one
  error.requestId, error.attempts, error.apiErrors;

  // Schedule your own backoff from the server's number; fall back when absent.
  const retryAt = new Date(Date.now() + (error.retryAfterSeconds ?? 5) * 1000);
}

// 2. Bounded automatic retry. Retry-After wins over computed backoff, and
//    retries stay finite — the SDK never retries indefinitely.
await client.nonprofits.check(ein, { retry: { maxRetries: 1, respectRetryAfter: true } });

// 3. Reduce pressure rather than absorb rejections: cap the outbound rate, keep
//    your own concurrency small, and prefer one bulk call to a fan-out of
//    single ones. The SDK does not queue on your behalf.
const paced = new PactmanClient({ apiKey, maxRequestsPerSecond: 3, retry: { maxRetries: 2 } });
```

#### EX-23 — Transient failures and retries

Transient 5xx and connection failures retried with jittered backoff; auth, validation and not-found never retried. [Full source](https://github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks/blob/master/nodejs/examples/ex-23-transient-retries.mjs)

```js
import { PactmanNetworkError, PactmanNotFoundError } from '@pactmandev/nonprofit-check-plus';

// Two 503s absorbed, one successful result returned to the caller. Backoff
// grows exponentially and is jittered, so parallel clients scatter.
const result = await client.nonprofits.check(ein, {
  retry: { maxRetries: 3, initialDelayMs: 500, maxDelayMs: 8_000 },
});

// Never retried, whatever retryableStatuses contains. Retrying a 404 cannot
// make a record exist; retrying a rejected key just burns it three times.
try {
  await client.nonprofits.check(missingEin, { retry: { maxRetries: 5, retryableStatuses: [404, 500] } });
} catch (error) {
  if (error instanceof PactmanNotFoundError) error.attempts; // 1
}

// A connection that never reached a server: retried, then surfaced with the
// attempt count. Local validation never reaches the network at all.
try {
  await unreachable.nonprofits.check(ein);
} catch (error) {
  if (error instanceof PactmanNetworkError) error.attempts;
}

// A retried failure that exhausts its budget is an outage. Record it as "not
// checked", never as a pass.
```

#### EX-24 — Timeouts and cancellation

`PactmanTimeoutError` and `AbortSignal` cancellation kept distinguishable, with no work left running. [Full source](https://github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks/blob/master/nodejs/examples/ex-24-timeout-and-cancellation.mjs)

```js
import { PactmanNetworkError, PactmanTimeoutError } from '@pactmandev/nonprofit-check-plus';

// Two different events, two different types. Conflating them hides which side
// gave up: a timeout means raise the budget or shed load; a cancellation means
// the caller went away.
try {
  await client.nonprofits.check(ein, { timeoutMs: 250, retry: false });
} catch (error) {
  if (error instanceof PactmanTimeoutError) {
    error.timeoutMs; // the deadline you configured expired
    error.category; // "timeout", origin "local"
  }
}

const controller = new AbortController();
const timer = setTimeout(() => controller.abort(new Error('user navigated away')), 200);

try {
  await client.nonprofits.check(ein, { signal: controller.signal, timeoutMs: 10_000 });
} catch (error) {
  // PactmanNetworkError, category "network", origin "local".
  // Aborting cancels the in-flight attempt and every retry still planned;
  // aborting before the call means no request is made at all.
  if (error instanceof PactmanNetworkError) error.cause;
} finally {
  clearTimeout(timer); // a stray timer is exactly the unbounded work this avoids
}
```

#### EX-25 — Raw response and forward compatibility

An approved fixture from a newer API version: unknown fields and an unknown enum value, both readable, neither fatal. [Full source](https://github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks/blob/master/nodejs/examples/ex-25-raw-and-forward-compat.mjs)

```js
const result = await client.nonprofits.check(ein);
const { nonprofit } = result;

// Known fields deserialize exactly as they always have.
getBmf(nonprofit)?.status;

// Fields this SDK version does not declare ride along on the same object. In
// TypeScript they are reachable through the index signature, typed as
// `unknown`, so you narrow them deliberately. No cast, no upgrade.
const registration = nonprofit['state_charity_registration_status'];

if (typeof registration === 'string') {
  // …
}

// An unrecognized value in a documented field. This is the case that breaks
// applications which map eagerly into an enum and default the miss.
const KNOWN_FOUNDATION_TYPES = new Set(['pc', 'pf', 'po']);
const foundationType = getBmf(nonprofit)?.foundation_type_code;

const handled = KNOWN_FOUNDATION_TYPES.has(foundationType)
  ? 'a known classification'
  : 'unknown — routed to review, not defaulted to a known type';

result.raw; // the parsed body, unmodified — persist it to prove what the API said
result.raw.data === nonprofit; // true
```

### Bulk

#### EX-17 — Bulk screening of a list

Screening a grantee list, iterating organization-level results and reading the response envelope. [Full source](https://github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks/blob/master/nodejs/examples/ex-17-bulk-screening.mjs)

```js
import { getAroe, getBmf, getOfac, getPub78 } from '@pactmandev/nonprofit-check-plus';

// One bulk request is one round trip and one rate-limit slot. Prefer it to a
// loop of single checks.
const result = await client.nonprofits.checkBulk(portfolio.map(entry => entry.ein));

result.status, result.raw.code, result.timeTakenMs, result.checkCount;
result.organizations.length, result.errors.length, result.notFoundEins;

// Index by EIN. The response is a set of matched records, not a row-for-row
// answer to your input list — see EX-18.
const byEin = new Map(result.organizations.map(org => [org.ein, org]));

for (const entry of portfolio) {
  const org = byEin.get(entry.ein);

  if (!org) continue; // no record returned — not a pass

  const bmf = getBmf(org);
  const pub78 = getPub78(org);
  const aroe = getAroe(org);
  const ofac = getOfac(org);

  console.log(org.ein, bmf?.status, pub78?.verified, Boolean(aroe?.revocation_date), ofac?.status);
}

for (const detail of result.errors) {
  detail.resource, detail.code, detail.reason, detail.eins;
}
```

#### EX-18 — Input order and duplicate EINs

Response order does not follow request order, duplicates collapse in the response but still bill, and usage is read rather than inferred. [Full source](https://github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks/blob/master/nodejs/examples/ex-18-bulk-order-and-duplicates.mjs)

```js
// Deliberately unsorted, with one EIN repeated. The SDK sends them exactly as
// supplied: it does not reorder and it does not deduplicate.
const requested = ['996589560', '411787097', '996589560', '135562308'];

const before = await client.nonprofits.check('411787097');
const result = await client.nonprofits.checkBulk(requested);

result.organizations.length; // 3 — the duplicate came back once

// Positional pairing is invalid. This is the pairing that always holds.
const byEin = new Map(result.organizations.map(org => [org.ein, org]));

// Usage is reported, not inferred. Every submitted EIN is billable, duplicates
// included, so a count derived from unique inputs will disagree with the invoice.
(result.checkCount ?? 0) - (before.checkCount ?? 0);

// Opt in when duplicates are an artifact of your data rather than intent.
await client.nonprofits.checkBulk(requested, { dedupe: true });
```

#### EX-19 — Partial success and item-level errors

Mixed outcomes on one HTTP 200: usable records, item-level errors, and a full input reconciliation. [Full source](https://github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks/blob/master/nodejs/examples/ex-19-bulk-partial-success.mjs)

```js
const submitted = ['411787097', '999999999', '996589560', '123456789'];
const result = await client.nonprofits.checkBulk(submitted);

result.status; // 200 — some matched and some did not, which is a success
result.organizations; // ordinary records; nothing about a sibling failure degrades them
result.errors; // [{ resource, code, reason, eins }]
result.notFoundEins;

// Reconcile every input against an outcome. This is the loop that keeps a
// portfolio import honest.
const matched = new Map(result.organizations.map(org => [org.ein, org]));
const missing = new Set(result.notFoundEins);

for (const ein of submitted) {
  const outcome = matched.has(ein)
    ? 'matched'
    : missing.has(ein)
      ? 'no record — reported in errors'
      : 'UNACCOUNTED FOR — do not treat as checked';
}

// An EIN the API has no record for is a gap in the data, not a negative finding
// about the organization. Route it to review; do not record it as "screened".
```

#### EX-20 — Batch-size validation and chunking

Empty and over-limit batches rejected against `MAX_BULK_EINS`, plus chunking a larger list yourself. [Full source](https://github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks/blob/master/nodejs/examples/ex-20-bulk-batch-limits.mjs)

```js
import { MAX_BULK_EINS, PactmanBadRequestError, PactmanValidationError } from '@pactmandev/nonprofit-check-plus';

MAX_BULK_EINS; // 50 — import it; do not copy the number into your own constants file

try {
  await client.nonprofits.checkBulk([]); // empty
  await client.nonprofits.checkBulk(oversized); // MAX_BULK_EINS + 1
} catch (error) {
  if (error instanceof PactmanValidationError) {
    error.origin; // "local" — nothing was sent
  }
}

// If the server ever tightens its limit below the SDK's constant, the local
// check passes and the server answers 400. That message is authoritative:
// catch PactmanBadRequestError and log apiErrors[].reason verbatim.

// The SDK never chunks for you, because splitting one batch would quietly turn
// one billable request into several. Do it deliberately.
const batches = [];

for (let index = 0; index < eins.length; index += MAX_BULK_EINS) {
  batches.push(eins.slice(index, index + MAX_BULK_EINS));
}
```

#### EX-21 — Billing-cycle usage tracking

`nonprofit_check_count` as a cumulative billing-cycle total that resets each cycle — never a per-request size. [Full source](https://github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks/blob/master/nodejs/examples/ex-21-usage-tracking.mjs)

```js
const first = await client.nonprofits.check(einA);
const bulk = await client.nonprofits.checkBulk([einA, einB, einC]);

first.checkCount; // cycle total, e.g. 1_281
bulk.checkCount; // cycle total again, e.g. 1_284 — not 3
(bulk.checkCount ?? 0) - (first.checkCount ?? 0); // what the bulk call consumed

// EINs with no record are not billed, so a delta can be smaller than the batch.
// At the start of a new billing cycle this counter resets to zero.

// Alerting needs your plan's allowance, which the check endpoints do not
// report. Keep it in your own configuration.
const allowance = Number(process.env.PACTMAN_PLAN_ALLOWANCE ?? 0);
const utilisation = allowance > 0 ? (bulk.checkCount ?? 0) / allowance : null;

// Label this metric "checks used this billing cycle" wherever it is displayed.
// Labelling it "checks in this request" makes a dashboard that resets monthly
// look like a dashboard that is broken.
```

### End-to-end workflows

#### EX-26 — Donation-platform onboarding

Donation-platform onboarding: collect, check, inspect every source, route to approve, reject or review. [Full source](https://github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks/blob/master/nodejs/examples/ex-26-onboarding-workflow.mjs)

```js
// This fictional platform's rules, in one place, reviewable by its compliance
// team. Read them as an illustration of where your policy lives.
const POLICY = { staleAfterDays: 120, requirePub78Listing: true };

async function onboard(applicant) {
  let result;

  try {
    result = await client.nonprofits.check(applicant.ein);
  } catch (error) {
    // A failed lookup is not a rejection. Nothing was learned, so nothing can
    // be concluded — the applicant waits, they are not turned away.
    return { decision: 'manual_review', reasons: ['the check could not be completed'] };
  }

  const { nonprofit } = result;

  if (!nonprofit) return { decision: 'manual_review', reasons: ['no record for this EIN'] };

  const aroe = getAroe(nonprofit);
  const ofac = getOfac(nonprofit);
  const pub78 = getPub78(nonprofit);
  const reasons = [];

  if (aroe?.revocation_date && !aroe.reinstatement_date) {
    return { decision: 'reject', reasons: ['Exemption revoked with no reinstatement.'] };
  }

  if (ofac?.status && /UID:/i.test(ofac.status)) {
    return { decision: 'reject', reasons: ['Possible OFAC SDN match.'] };
  }

  if (nonprofit.irs_bmf_pub78_conflict === true) reasons.push('IRS sources disagree.');
  if (POLICY.requirePub78Listing && pub78?.verified !== true) reasons.push('Not listed in Publication 78.');
  if (!nameAgrees(applicant.legalName, nonprofit)) reasons.push('Submitted name did not match.');

  return reasons.length === 0
    ? { decision: 'approve', reasons: ['Every check this platform requires was satisfied.'] }
    : { decision: 'manual_review', reasons };
}

// The platform decided; the SDK did not.
```

#### EX-27 — DAF grant-recommendation screening

DAF grant-recommendation screening, with a stricter policy than EX-26 over identical data. [Full source](https://github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks/blob/master/nodejs/examples/ex-27-daf-grant-screening.mjs)

```js
// One bulk call for the whole recommendation batch.
const result = await client.nonprofits.checkBulk(recommendations.map(entry => entry.ein));
const byEin = new Map(result.organizations.map(org => [org.ein, org]));
const decisions = [];

for (const recommendation of recommendations) {
  const org = byEin.get(recommendation.ein);

  if (!org) {
    // No record was returned. Nothing was verified.
    decisions.push({ ...recommendation, outcome: 'held', queue: 'grants_review' });
    continue;
  }

  const aroe = getAroe(org);
  const ofac = getOfac(org);
  const bmf = getBmf(org);

  const [outcome, queue] =
    ofac?.status && /UID:/i.test(ofac.status)
      ? ['blocked', 'sanctions_review']
      : aroe?.revocation_date && !aroe.reinstatement_date
        ? ['blocked', 'tax_status_review']
        : org.irs_bmf_pub78_conflict === true
          ? ['held', 'source_conflict_review']
          : bmf?.foundation_type_code === 'pf'
            ? ['held', 'expenditure_responsibility'] // not refused: a different path
            : ['advanced', 'ready_for_approval'];

  decisions.push({ ...recommendation, outcome, queue, screenedAt: new Date().toISOString(), requestId: result.requestId });
}

// Same API data as EX-26, different obligations, different outcomes. That
// difference is precisely why the SDK does not decide.
```

#### EX-28 — CRM enrichment and synchronization

CRM sync keyed on EIN, where a `null` from the API never erases better customer data. [Full source](https://github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks/blob/master/nodejs/examples/ex-28-crm-enrichment.mjs)

```js
const SYNCED_FIELDS = [
  'organization_name', 'organization_name_aka',
  'address_line1', 'address_line2', 'city', 'state', 'state_name', 'zip',
  'subsection_description', 'foundation_type_description',
  'bmf_status', 'pub78_verified', 'pactman_org_url', 'organization_info_last_modified',
];

// A field is written only when the API returned a usable value. `null` and
// absent both mean "no update available" — never "clear this". A sync that
// overwrites a good, human-entered address with null is a data-loss bug that
// looks like a feature until someone notices.
function merge(record, nonprofit) {
  const next = { ...record };

  for (const key of SYNCED_FIELDS) {
    const incoming = nonprofit[key];

    if (incoming === null || incoming === undefined) continue; // keep what the CRM holds

    next[key] = incoming;
  }

  return next;
}

// EIN is the join key: stable, returned on every record, already in your CRM.
// Names change; EINs do not.
const result = await client.nonprofits.checkBulk([...crm.keys()]);
const byEin = new Map(result.organizations.map(org => [org.ein, org]));

for (const [ein, record] of crm) {
  const nonprofit = byEin.get(ein);

  if (!nonprofit) {
    // A failed lookup is not new information. Leave the row untouched.
    crm.set(ein, { ...record, lastSyncAttemptAt: new Date().toISOString() });
    continue;
  }

  crm.set(ein, {
    ...merge(record, nonprofit),
    verifiedAt: new Date().toISOString(), // without this, a row checked yesterday and
    verificationRequestId: result.requestId, // one imported in 2019 look identical
    verificationReportDate: nonprofit.report_date,
  });
}
```

#### EX-29 — Pre-disbursement recheck

Recheck immediately before a payout; a material change pauses it and both evidence sets are kept. [Full source](https://github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks/blob/master/nodejs/examples/ex-29-pre-disbursement-recheck.mjs)

```js
// Changes that stop a disbursement outright at this organization.
const BLOCKING = new Set([
  'revocation_code', 'revocation_date', 'ofac_state',
  'bmf_status', 'pub78_verified', 'irs_bmf_pub78_conflict',
]);

async function recheck(payment, stored) {
  let result;

  try {
    // Retries stay on: a transient failure should be absorbed, not turned into
    // a false "changed" signal.
    result = await client.nonprofits.check(payment.ein, { timeoutMs: 10_000 });
  } catch (error) {
    // An unreachable API is not evidence that anything is fine.
    return { decision: 'hold', reason: 'recheck_failed' };
  }

  if (!result.nonprofit) return { decision: 'hold', reason: 'no_record' };

  // collectFindings is your own projection of the response — store findings,
  // not a verdict: "approved" alone cannot be re-examined.
  const current = collectFindings(result.nonprofit);
  const changes = Object.keys(current).filter(key => current[key] !== stored.findings[key]);
  const blocking = changes.filter(key => BLOCKING.has(key));

  // Both snapshots are kept. Neither overwrites the other.
  return {
    decision: blocking.length > 0 ? 'hold' : 'release',
    priorVerification: stored,
    currentVerification: {
      checkedAt: new Date().toISOString(),
      requestId: result.requestId,
      reportDate: result.nonprofit.report_date,
      findings: current,
    },
    changes,
  };
}

// An organization approved at onboarding is not an organization approved today.
// Recheck as close to the money movement as your workflow allows.
```

#### EX-30 — Scheduled portfolio re-verification

Scheduled bulk re-verification with a diff against the last run and an explainable audit trail. [Full source](https://github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks/blob/master/nodejs/examples/ex-30-portfolio-reverification.mjs)

```js
import { MAX_BULK_EINS } from '@pactmandev/nonprofit-check-plus';

// Identify the rules that produced an outcome, so old entries stay readable.
const POLICY_VERSION = '2026.02-portfolio-rev3';
const RE_REVIEW_INTERVAL_DAYS = 90;

const records = new Map();

for (const eins of chunk(portfolio.map(entry => entry.ein), MAX_BULK_EINS)) {
  const result = await client.nonprofits.checkBulk(eins);

  for (const org of result.organizations) {
    records.set(org.ein, { org, requestId: result.requestId, status: result.status });
  }

  // An EIN that produced no record is unverified this cycle, not clean.
  for (const ein of result.notFoundEins) {
    records.set(ein, { org: null, requestId: result.requestId, status: result.status });
  }
}

for (const entry of portfolio) {
  const record = records.get(entry.ein);
  const findings = record?.org ? collectFindings(record.org) : null;

  // A first run has nothing to compare against; say so rather than reporting
  // every field as "changed".
  const isBaseline = entry.lastFindings === null;
  const changes = isBaseline || !findings ? [] : diffFindings(entry.lastFindings, findings);

  auditLog.push({
    ein: entry.ein,
    checkedAt: runStartedAt.toISOString(),
    requestId: record?.requestId ?? null, // identifiers are stored; API keys never are
    policyVersion: POLICY_VERSION,
    outcome, // suspend | review | retain
    changes,
    findings,
    nextReviewDue: new Date(runStartedAt.getTime() + RE_REVIEW_INTERVAL_DAYS * 86_400_000).toISOString(),
  });

  entry.lastFindings = findings; // carry the snapshot forward for the next run
}

// What makes an audit trail useful is the evidence next to the outcome: when
// the check ran, which request it was, what each source said, and which policy
// version read them.
```

### One thing every example repeats

The SDK reports what the API returned. It produces no `approved`, `eligible` or `safe` verdict, and no boolean summarizing a source the API does not itself express as a boolean. Whether an organization qualifies for a donation, a grant, a match or a payout is a determination for your own legal, compliance and risk policy — which is why the routing logic in these examples lives in the example, never in the library.

## Support

- API documentation: <https://pactman.org/nonprofitcheckplus-api/docs>
- Pactman: <https://pactman.org>
- Issues: <https://github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks/issues>

## License

MIT — see [LICENSE](./LICENSE).
