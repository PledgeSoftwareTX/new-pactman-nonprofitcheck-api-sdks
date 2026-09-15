# pactman-nonprofit-check-plus (Go)

Official Go SDK for the **Pactman Nonprofit Check Plus API**. Look up US nonprofits by EIN and read the IRS and OFAC findings behind the result.

- Typed models for every documented response field, with every field the API sent — known to this SDK or not — always reachable
- Local EIN normalization and validation, so malformed input never costs a request
- A structured error taxonomy you branch on with `errors.Is` and `errors.As`, never by parsing message strings
- `context.Context` cancellation, a finite per-attempt timeout, bounded retries with jittered backoff, and `Retry-After` support
- Safe for concurrent use, with no dependencies outside the standard library

> **Server-side only.** Your API key is a private credential. Do not build this client into anything that ships to an end user.

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
- [Concurrency and client lifecycle](#concurrency-and-client-lifecycle)
- [Headers and your own HTTP client](#headers-and-your-own-http-client)
- [Security](#security)
- [What this SDK does not tell you](#what-this-sdk-does-not-tell-you)
- [API reference](#api-reference)
- [Coming from the Node.js SDK](#coming-from-the-nodejs-sdk)
- [Examples](#examples)
- [Development](#development)
- [Versioning and releases](#versioning-and-releases)
- [License](#license)

---

## Requirements

- Go **1.22 or newer**
- A Pactman API key with Nonprofit Check access

## Installation

```bash
go get github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks/go@latest
```

```go
import "github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks/go/pactman"
```

## Configuring your API key

Load the key from the environment or a secret manager. Never commit it and never inline it in source.

```go
client, err := pactman.NewClient(os.Getenv("PACTMAN_API_KEY"))
if err != nil {
	return err
}
```

The key is validated locally. An empty or whitespace-only key returns a `*pactman.ConfigurationError` from `NewClient`, before any network call.

Every request carries the key as `Authorization: Bearer <key>`. It never appears in an error, in `json.Marshal(client)`, in `slog` output, or in `fmt` output under any verb.

## Quick start

```go
ctx := context.Background()

result, err := client.Nonprofits.Check(ctx, "41-1787097")
if err != nil {
	return err
}

if n := result.Nonprofit; n != nil && n.OrganizationName != nil {
	fmt.Println(*n.OrganizationName) // "EXAMPLE NONPROFIT"
}

if result.CheckCount != nil {
	fmt.Println(*result.CheckCount) // checks used so far this billing cycle
}
```

## Environment and base URL

Production is the default and the only named environment. Pactman's QA and sandbox hosts are internal and are not selectable from this package.

```go
// These are equivalent.
pactman.NewClient(apiKey)
pactman.NewClient(apiKey, pactman.WithEnvironment(pactman.EnvironmentProduction))
```

For a local mock server, a proxy, or a host Pactman has given you directly, use `WithBaseURL`. It replaces the environment and is validated locally — a malformed URL returns a `*ConfigurationError`.

```go
client, _ := pactman.NewClient(apiKey, pactman.WithBaseURL("http://127.0.0.1:4010"))

client.BaseURL()     // "http://127.0.0.1:4010"
client.Environment() // "" — an explicit host, not a named environment
```

## Single check

```go
result, err := client.Nonprofits.Check(ctx, "41-1787097")

result.Nonprofit  // *pactman.Nonprofit, nil when the API returned no record
result.CheckCount // *int64 — see "Usage and billing cycle"
result.TimeTaken  // *time.Duration — server-side processing time
result.Status     // HTTP status
result.RequestID  // correlation ID, when the server sends one
result.Raw        // the response envelope, unmodified
```

`"41-1787097"` and `"411787097"` are the same request — the EIN is normalized before the URL is built.

## Bulk check

```go
result, err := client.Nonprofits.CheckBulk(ctx, []string{"41-1787097", "996589560", "999999999"})
if err != nil {
	return err
}

for _, org := range result.Organizations {
	fmt.Println(*org.EIN, *org.OrganizationName)
}

// EINs with no record are not an error — they come back on a 200 response.
fmt.Println(result.NotFoundEINs) // [999999999]
```

|                    |                                                                                                                                   |
| ------------------ | --------------------------------------------------------------------------------------------------------------------------------- |
| **Batch limit**    | 50 EINs per request, enforced locally before sending. Exported as `pactman.MaxBulkEINs`.                                          |
| **Chunking**       | None. Larger inputs return a `*ValidationError` rather than silently splitting into several billable requests.                   |
| **Request order**  | Your EINs are sent exactly as supplied. The SDK never reorders them.                                                              |
| **Response order** | Not guaranteed to match. The API matches by set membership — index `Organizations` by EIN, never pair them positionally.          |
| **Duplicates**     | Sent as supplied, because each one is billable. A repeated EIN still returns one record. Pass `pactman.WithDedupe()` to collapse. |
| **Empty input**    | Returns a `*ValidationError` locally.                                                                                             |
| **One bad EIN**    | The whole batch is rejected locally; `Issues` identifies every failing index. Nothing is sent.                                    |
| **No matches**     | A batch where nothing matched is `ErrNotFound`; a batch where some matched is a 200 with the rest in `NotFoundEINs`.              |

```go
// Index by EIN — the pairing that always holds.
byEIN := make(map[string]*pactman.Nonprofit, len(result.Organizations))
for _, org := range result.Organizations {
	if org.EIN != nil {
		byEIN[*org.EIN] = org
	}
}
```

## Usage and billing cycle

`nonprofit_check_count`, surfaced as `result.CheckCount`, is the number of checks your account has consumed **so far in the current billing cycle**, including the request that returned it. It resets when a new cycle starts.

It is not the size of the request you just made. A bulk call for five EINs does not return `5`. To learn what a call cost, take the difference between two responses. EINs with no matching record are not billed, so a difference can be smaller than the batch you sent.

## Inspecting source-specific findings

The API returns source fields flat on the organization (`Pub78*`, `BMF*`, `OFACStatus`, and the revocation fields). Read them directly, or through the grouped views — which copy fields 1:1 and derive nothing.

```go
n := result.Nonprofit

if pub78 := n.Pub78(); pub78 == nil {
	fmt.Println("Publication 78 data was not returned for this organization.")
} else if pub78.Verified != nil {
	fmt.Println(*pub78.Verified)
}

bmf := n.BMF()   // IRS Business Master File
aroe := n.AROE() // IRS Automatic Revocation of Exemption
ofac := n.OFAC() // OFAC Specially Designated Nationals — a sentence, not a flag
```

Each view is `nil` only when the API returned **none** of that source's fields. That keeps _"the source was not returned"_ distinct from an explicit negative such as `pub78_verified: false`. Every view is safe to call on a nil `*Nonprofit`.

**On OFAC:** the API returns `ofac_status` as prose. This SDK deliberately has no `HasOFACMatch`, because deriving one would mean pattern-matching English that could be reworded at any time.

## Response models and raw data

Each wire field has a Go field — `organization_name` is `OrganizationName`, `pub78_verified` is `Pub78Verified` — and the struct tags hold the wire names. Every field is a pointer or a slice, because the API omits fields it has no data for.

**A nil field means the API returned no value.** Whether it sent no field or sent `null`, and anything this SDK does not declare, is on `Fields`, which holds the record exactly as the API sent it:

```go
n.Fields.Has("ofac_status")    // the API sent the field, null included
n.Fields.IsNull("ofac_status") // it sent null

raw, ok := n.Fields.Get("some_future_field") // readable without an SDK upgrade
var value string
_ = json.Unmarshal(raw, &value)
```

Decoding is lenient field by field. If the API changes the type of one field, that field reads as nil — a string field keeps the value as its JSON text — the original stays in `Fields`, and the rest of the record decodes normally.

`result.Raw` is the envelope. `result.Raw.Code` and `result.Raw.Message` are typed, and `json.Marshal(result.Raw)` returns the response body exactly as received — persist that to prove what the API said. Models are read views: `json.Marshal(nonprofit)` likewise returns the record as it arrived.

## EIN validation and normalization

```go
pactman.NormalizeEIN("41-1787097") // "411787097", nil
pactman.IsValidEIN("4117870")      // false
pactman.NormalizeEINs(eins)        // every failure at once, by index
```

Accepted: nine digits, with or without the conventional hyphen after the two-digit prefix, ignoring surrounding whitespace. No IRS prefix rules are applied.

```go
_, err := client.Nonprofits.CheckBulk(ctx, []string{"411787097", "nope", "1234"})

var invalid *pactman.ValidationError
if errors.As(err, &invalid) {
	for _, issue := range invalid.Issues {
		fmt.Println(issue.Index, issue.Value, issue.Message)
	}
}
```

> Formatting validation confirms only that a value is shaped like an EIN. It says nothing about tax-exempt status, identity, eligibility, or good standing.

## Error handling

Every error implements `pactman.Error`, with a stable `Category()` and an `Origin()` of `local` or `api`. Branch with `errors.Is` on the sentinels, or `errors.As` on the concrete types — both work through any wrapping:

```go
var apiErr *pactman.APIError

switch {
case errors.Is(err, pactman.ErrValidation):
	// Bad input. Nothing was sent.
case errors.Is(err, pactman.ErrAuthentication):
	// The key was rejected.
case errors.Is(err, pactman.ErrRateLimit):
	errors.As(err, &apiErr) // apiErr.RetryAfter, when the server sent one
case errors.Is(err, pactman.ErrTimeout):
	// An attempt exceeded the timeout.
case errors.As(err, &apiErr):
	fmt.Println(apiErr.Status, apiErr.RequestID, apiErr.APIErrors)
}
```

| Category                 | Sentinel            | Type                  | Origin | Raised for                                      |
| ------------------------ | ------------------- | --------------------- | ------ | ----------------------------------------------- |
| `CategoryConfiguration`  | `ErrConfiguration`  | `*ConfigurationError` | local  | Unusable client options                         |
| `CategoryValidation`     | `ErrValidation`     | `*ValidationError`    | local  | Input or a per-call option rejected before send |
| `CategoryBadRequest`     | `ErrBadRequest`     | `*APIError`           | api    | HTTP 400                                        |
| `CategoryAuthentication` | `ErrAuthentication` | `*APIError`           | api    | HTTP 401                                        |
| `CategoryAuthorization`  | `ErrAuthorization`  | `*APIError`           | api    | HTTP 403                                        |
| `CategoryNotFound`       | `ErrNotFound`       | `*APIError`           | api    | HTTP 404                                        |
| `CategoryRateLimit`      | `ErrRateLimit`      | `*APIError`           | api    | HTTP 429                                        |
| `CategoryServer`         | `ErrServer`         | `*APIError`           | api    | HTTP 5xx                                        |
| `CategoryAPI`            | —                   | `*APIError`           | api    | Any other unexpected response                   |
| `CategoryTimeout`        | `ErrTimeout`        | `*TimeoutError`       | local  | An attempt exceeded the configured timeout      |
| `CategoryNetwork`        | `ErrNetwork`        | `*NetworkError`       | local  | No response, or the caller's context ended      |

`*APIError` carries `Status`, `APICode`, `APIMessage`, `APIErrors`, `RequestID`, `RetryAfter`, `Attempts` and `Body`. When a body cannot be decoded, the metadata is still there and `Body` holds what the server actually sent. `json.Marshal(err)` gives a sanitized form, without the body, that is safe to log.

## Timeouts and cancellation

The default timeout is **30 seconds** per attempt, exported as `pactman.DefaultTimeout`. It is always finite — there is no way to disable it.

```go
client, _ := pactman.NewClient(apiKey, pactman.WithTimeout(10*time.Second))

// Or per call.
client.Nonprofits.Check(ctx, ein, pactman.WithTimeout(5*time.Second))
```

The context cancels the in-flight request _and_ any planned retries. When your context ends, the call returns a `*NetworkError` that unwraps to `ctx.Err()`, so `errors.Is(err, context.Canceled)` and `errors.Is(err, context.DeadlineExceeded)` work.

The SDK's own per-attempt timeout is a `*TimeoutError`, and it deliberately does **not** match `context.DeadlineExceeded`. The two mean different things — raise the budget or shed load, versus the caller went away — and conflating them hides which side gave up.

## Retries

Enabled by default: up to **2 retries** (3 attempts), exponential backoff from 500ms with full jitter, capped at 8 seconds per delay.

```go
policy := pactman.DefaultRetryPolicy()
policy.MaxRetries = 3
policy.RetryableStatuses = []int{429, 500, 502, 503, 504}

client, _ := pactman.NewClient(apiKey, pactman.WithRetryPolicy(policy))

// Disable entirely.
pactman.NewClient(apiKey, pactman.WithoutRetries())

// Or override per call: just the count, or a whole policy built from the client's.
client.Nonprofits.Check(ctx, ein, pactman.WithMaxRetries(0))

custom := client.RetryPolicy()
custom.InitialDelay = time.Second
client.Nonprofits.Check(ctx, ein, pactman.WithRetryPolicy(custom))
```

Retried: 429, 500, 502, 503, 504, timeouts and transient network failures. **Never** retried: 400, 401, 403, 404, local validation errors and a cancelled context — regardless of `RetryableStatuses`. A valid `Retry-After` always takes precedence over computed backoff.

## Rate limits

The API returns HTTP 429 when you exceed your limit. The SDK maps that to `ErrRateLimit` and exposes the server's `Retry-After`:

```go
var apiErr *pactman.APIError
if errors.Is(err, pactman.ErrRateLimit) && errors.As(err, &apiErr) && apiErr.RetryAfter != nil {
	fmt.Println("retry in", *apiErr.RetryAfter)
}
```

With retries enabled, a 429 is retried automatically after the server's `Retry-After`, falling back to backoff when none is sent.

An optional client-side ceiling is available and off by default. It is shared by every goroutine using the client:

```go
client, _ := pactman.NewClient(apiKey, pactman.WithMaxRequestsPerSecond(3))
```

Server-side limits are authoritative and may vary; treat this as a courtesy throttle, not a guarantee. Prefer the bulk endpoint over concurrent single checks, and keep your own concurrency bounded — the SDK does not queue on your behalf.

## Concurrency and client lifecycle

Build one `*pactman.Client` per process and share it. It is safe for concurrent use, reuses connections through its HTTP client, and carries the throttle state when a ceiling is set. There is nothing to close.

## Headers and your own HTTP client

```go
// Extra headers, on every request or on one call.
client, _ := pactman.NewClient(apiKey, pactman.WithHeader("X-Tenant", "acme"))
client.Nonprofits.Check(ctx, ein, pactman.WithHeader("X-Trace", traceID))

// Your own transport: an *http.Client, or anything with Do(*http.Request).
client, _ = pactman.NewClient(apiKey, pactman.WithHTTPClient(&http.Client{Transport: myTransport}))
```

Headers cannot override `Authorization`, `Accept`, `User-Agent` or `Content-Type`. The per-attempt timeout is applied through the request context, so your HTTP client needs no timeout of its own.

## Security

- Load the key from an environment variable or secret manager. Never commit it.
- **Server-side only.** A key shipped inside a client application belongs to anyone who unpacks it.
- The key is redacted from every diagnostic surface: error messages and their JSON form, `json.Marshal(client)`, `slog`, and every `fmt` verb.
- Rotate the key if it is ever printed, logged, or committed.
- Nonprofit records may be subject to your own retention and privacy obligations. Storing responses is your call, not the SDK's.

## What this SDK does not tell you

The SDK exposes what the API returns and nothing more. It deliberately provides **no** composite approved, eligible, or safe verdict, and no boolean summarizing a source that the API does not itself express as a boolean.

A successful check is data, not a decision. Whether an organization qualifies for a grant, a donation, a match, or a partnership is a determination for your own legal, compliance, grantmaking, and risk policy.

## API reference

**Client** — `pactman.NewClient(apiKey string, opts ...pactman.ClientOption) (*pactman.Client, error)`

| Option                        | Accepted by               | Default                  |                                                 |
| ----------------------------- | ------------------------- | ------------------------ | ----------------------------------------------- |
| `WithEnvironment(e)`          | `NewClient`               | `EnvironmentProduction`  | Named environment.                              |
| `WithBaseURL(u)`              | `NewClient`               | —                        | Explicit host; replaces the environment.        |
| `WithTimeout(d)`              | `NewClient`, every call   | 30s                      | Per-attempt timeout.                            |
| `WithRetryPolicy(p)`          | `NewClient`, every call   | `DefaultRetryPolicy()`   | Retry policy.                                   |
| `WithMaxRetries(n)`           | `NewClient`, every call   | 2                        | Changes only the retry count.                   |
| `WithoutRetries()`            | `NewClient`, every call   | —                        | One attempt.                                    |
| `WithMaxRequestsPerSecond(r)` | `NewClient`               | off                      | Client-side throttle.                           |
| `WithHeader(name, value)`     | `NewClient`, every call   | —                        | Extra header; cannot override owned headers.    |
| `WithHTTPClient(c)`           | `NewClient`               | `&http.Client{}`         | Your own `HTTPDoer`.                            |
| `WithDedupe()`                | `CheckBulk`               | off                      | Collapse duplicate EINs before sending.         |

Accessors: `client.Nonprofits`, `client.BaseURL()`, `client.Environment()`, `client.Timeout()`, `client.RetryPolicy()`.

**Methods**

- `client.Nonprofits.Check(ctx, ein, opts...)` → `(*SingleCheckResult, error)`
- `client.Nonprofits.CheckBulk(ctx, eins, opts...)` → `(*BulkCheckResult, error)`

**Helpers** — `NormalizeEIN`, `NormalizeEINs`, `IsValidEIN`, `SupportedEnvironments`, `BaseURLForEnvironment`, `DefaultRetryPolicy`, and on `*Nonprofit`: `Pub78`, `BMF`, `AROE`, `OFAC`

**Constants** — `MaxBulkEINs`, `DefaultTimeout`, `DefaultEnvironment`, `EINLength`, `SingleCheckPath`, `BulkCheckPath`, `Version`

**Types** — `Nonprofit`, `OrganizationType`, `APIErrorDetail`, `Envelope`, `Object`, `Result`, `SingleCheckResult`, `BulkCheckResult`, `Pub78Source`, `BMFSource`, `AROESource`, `OFACSource`, `RetryPolicy`, `HTTPDoer`, and the error types above

Every exported identifier is documented: `go doc github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks/go/pactman`.

## Coming from the Node.js SDK

The Node.js SDK is the reference implementation; this package makes the same promises in Go's idiom.

| Node.js                                             | Go                                                               |
| --------------------------------------------------- | ---------------------------------------------------------------- |
| `new PactmanClient({ apiKey, timeoutMs: 10_000 })`  | `pactman.NewClient(apiKey, pactman.WithTimeout(10*time.Second))` |
| `{ signal }` and `AbortController`                  | the call's `context.Context`                                     |
| `retry: false` / `{ maxRetries: 1 }`                | `WithoutRetries()` / `WithMaxRetries(1)`                         |
| `checkBulk(eins, { dedupe: true })`                 | `CheckBulk(ctx, eins, pactman.WithDedupe())`                     |
| `error instanceof PactmanNotFoundError`             | `errors.Is(err, pactman.ErrNotFound)`                            |
| `error instanceof PactmanApiError`                  | `errors.As(err, &apiErr)` with `var apiErr *pactman.APIError`    |
| `error.retryAfterSeconds`                           | `apiErr.RetryAfter` (`*time.Duration`)                           |
| `nonprofit.organization_name`                       | `*nonprofit.OrganizationName`                                    |
| `nonprofit['some_future_field']`                    | `nonprofit.Fields.Get("some_future_field")`                      |
| `getPub78(nonprofit)`                               | `nonprofit.Pub78()`                                              |
| `result.raw`                                        | `result.Raw`, and `json.Marshal(result.Raw)` for the exact body  |
| `result.timeTakenMs`                                | `result.TimeTaken` (`*time.Duration`)                            |

## Examples

Thirty numbered examples live in [`examples/`](./examples), covering client
setup, every source on a record, each error category, bulk semantics and five
end-to-end workflows. They read `PACTMAN_API_KEY` from the environment and
contain no credentials. [`examples/README.md`](./examples/README.md) lists what
each one demonstrates.

```bash
cd go
PACTMAN_API_KEY=your_key go run ./examples/ex-01-secure-client-init
PACTMAN_API_KEY=your_key go run ./examples/quickstart 41-1787097
PACTMAN_API_KEY=your_key go run ./examples/bulk
PACTMAN_API_KEY=your_key go run ./examples/error-handling
```

Most of them need a record or a response production will not produce on request
— a revoked exemption, an OFAC match, an HTTP 429, a field newer than this SDK —
so they start the bundled fixture API themselves. `PACTMAN_BASE_URL` points them
somewhere else.

CI runs every example against that fixture API on every push. An example that
stops demonstrating what it claims exits non-zero and fails the build, rather
than going stale unnoticed in a directory nobody runs:

```bash
go run ./internal/devtools examples-smoke                     # pass/fail
EXAMPLES_VERBOSE=1 go run ./internal/devtools examples-smoke  # with output
go run ./internal/devtools examples-smoke ex-22 ex-23         # a subset
```

## Development

```bash
cd go
go vet ./... && go test -race ./...
go run ./internal/devtools mock 4010   # the fixture API, for pointing your own code at
```

`internal/contract/response-contract.json` is what this package promises each response looks like. It is a byte-identical copy of the Node SDK's `nodejs/src/response-contract.json` — the source of truth — and a test fails when the two differ, or when the Go models stop declaring exactly the fields it predicts. `internal/mockapi` is a port of the Node SDK's fixture server.

## Versioning and releases

The module path is `github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks/go`, and Go reads a module's version from its git tag. Because the module lives in the `go/` directory, a release is tagged with that prefix:

```bash
git tag go/v1.0.0 && git push origin go/v1.0.0
```

`pactman.Version` must match the tag; the `publish-go` workflow checks that, runs the suite, and asks proxy.golang.org to fetch the release. A tag cannot be changed once the proxy has served it — publish a new patch version instead.

## License

MIT — see [LICENSE](./LICENSE).
