# pactman-nonprofit-check-plus

Official Java SDK for the **Pactman Nonprofit Check Plus API**. Look up US nonprofits by EIN and read the IRS and OFAC findings behind the result.

- Typed accessors for every documented response field, with the raw payload always available
- Local EIN normalization and validation, so malformed input never costs a request
- A structured exception taxonomy you branch on by type, never by parsing message strings
- Finite default timeout, cancellation, bounded retries with jittered backoff, and `Retry-After` support
- **No runtime dependencies** — adding this SDK cannot collide with the Jackson or logging version your application already runs

> **Server-side only.** Your API key is a private credential. Do not construct this client in an Android app, a desktop binary, or anything else that ships to an end user.

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
- [Asynchronous calls](#asynchronous-calls)
- [Retries](#retries)
- [Rate limits](#rate-limits)
- [Client lifecycle and thread safety](#client-lifecycle-and-thread-safety)
- [Supplying your own HTTP client](#supplying-your-own-http-client)
- [Security](#security)
- [What this SDK does not tell you](#what-this-sdk-does-not-tell-you)
- [API reference](#api-reference)
- [Examples](#examples)
- [Building from source](#building-from-source)
- [Checking a live deployment](#checking-a-live-deployment)
- [Support](#support)
- [License](#license)

---

## Requirements

- **Java 11 or newer.** The transport is the JDK's own `java.net.http.HttpClient`, which arrived in 11.
- A Pactman API key with Nonprofit Check access

The artifact declares no runtime dependencies. JSON is decoded by a small internal reader, so this SDK never forces a Jackson version on your application.

## Installation

Maven:

```xml
<dependency>
  <groupId>org.pactman</groupId>
  <artifactId>pactman-nonprofit-check-plus</artifactId>
  <version>1.0.0</version>
</dependency>
```

Gradle:

```kotlin
implementation("org.pactman:pactman-nonprofit-check-plus:1.0.0")
```

The jar carries `Automatic-Module-Name: org.pactman.nonprofitcheckplus`, so it is usable from a modular application with `requires org.pactman.nonprofitcheckplus;`.

## Configuring your API key

Load the key from the environment or a secret manager. Never commit it, never inline it in source, and never ship it inside a client-side artifact.

```bash
# .env — excluded from version control
PACTMAN_API_KEY=your_api_key_here
```

```java
import org.pactman.nonprofitcheckplus.PactmanClient;

PactmanClient client = new PactmanClient(System.getenv("PACTMAN_API_KEY"));
```

The key is validated locally. A missing, empty, or whitespace-only key throws `PactmanConfigurationException` at construction, before any network call:

```java
new PactmanClient("");
// PactmanConfigurationException: The Pactman API key is empty. Check that the
// environment variable holding it is set.
```

Every request carries the key as `Authorization: Bearer <key>`. It never appears in logs, exception messages, `toString()`, or `toMap()`. A default header named `Authorization` is dropped rather than sent, so nothing a caller configures can ride along beside the real credential.

## Quick start

```java
import org.pactman.nonprofitcheckplus.PactmanClient;
import org.pactman.nonprofitcheckplus.models.SingleCheckResult;

try (PactmanClient client = new PactmanClient(System.getenv("PACTMAN_API_KEY"))) {
    SingleCheckResult result = client.nonprofits().check("41-1787097");

    System.out.println(result.getNonprofit().getOrganizationName()); // "EXAMPLE NONPROFIT"
    System.out.println(result.getNonprofit().getPub78Verified());    // true
    System.out.println(result.getCheckCount());  // checks used so far this billing cycle
}
```

`try`-with-resources is optional. `close()` only shuts down the thread pool the async methods use, and only if they were used — see [Client lifecycle](#client-lifecycle-and-thread-safety).

## Environment and base URL

Production is the default and the only named environment. Pactman's QA and sandbox hosts are internal and are not selectable from this package.

```java
import org.pactman.nonprofitcheckplus.PactmanEnvironment;
import org.pactman.nonprofitcheckplus.config.PactmanClientOptions;

// These are equivalent.
new PactmanClient(apiKey);
new PactmanClient(PactmanClientOptions.builder()
        .apiKey(apiKey)
        .environment(PactmanEnvironment.PRODUCTION)
        .build());
```

For a local mock server, a proxy, or a host Pactman has given you directly, set `baseUrl`. It overrides `environment`, and is validated locally — a malformed URL throws `PactmanConfigurationException` before a request is attempted.

```java
PactmanClient client = new PactmanClient(PactmanClientOptions.builder()
        .apiKey(apiKey)
        .baseUrl("http://127.0.0.1:4010")
        .build());

client.baseUrl();     // "http://127.0.0.1:4010"
client.environment(); // null — an explicit host, not a named environment
```

Only the target host changes. Request and response semantics are identical.

## Single check

```java
SingleCheckResult result = client.nonprofits().check("41-1787097");

result.getNonprofit();   // Nonprofit, or null when the API returned no record
result.getCheckCount();  // nonprofit_check_count — see "Usage and billing cycle"
result.getTimeTakenMs(); // server-side processing time
result.getStatus();      // HTTP status
result.getRequestId();   // correlation ID, when the server sends one
result.getRaw();         // the unmodified response envelope
```

`"41-1787097"` and `"411787097"` are the same request — the EIN is normalized before the URL is built.

## Bulk check

```java
BulkCheckResult result = client.nonprofits()
        .checkBulk(List.of("41-1787097", "996589560", "999999999"));

for (Nonprofit org : result.getOrganizations()) {
    System.out.println(org.getEin() + " " + org.getOrganizationName());
}

// EINs with no record are not an error — they come back on a 200 response.
System.out.println(result.getNotFoundEins()); // ["999999999"]
System.out.println(result.getCheckCount());
```

Behaviour worth knowing:

|                    |                                                                                                                                     |
| ------------------ | ----------------------------------------------------------------------------------------------------------------------------------- |
| **Batch limit**    | 50 EINs per request, enforced locally before sending. Published as `Endpoints.MAX_BULK_EINS`.                                        |
| **Chunking**       | None. Larger inputs throw rather than silently splitting into several billable requests.                                             |
| **Request order**  | Your EINs are sent exactly as supplied. The SDK never reorders them.                                                                 |
| **Response order** | Not guaranteed to match. The API matches by set membership — index `getOrganizations()` by EIN, never pair them positionally.        |
| **Duplicates**     | Sent as supplied, because each one is billable. A repeated EIN still returns one record. Pass `new BulkRequestOptions().dedupe(true)` to collapse. |
| **Empty input**    | Throws `PactmanValidationException` locally.                                                                                        |
| **One bad EIN**    | The whole batch is rejected locally, identifying the failing index. Nothing is sent.                                                 |
| **No matches**     | A batch where nothing matched is an error; a batch where some matched is a 200 with the rest in `getNotFoundEins()`.                 |

```java
// Opt in to deduplication.
client.nonprofits().checkBulk(eins, new BulkRequestOptions().dedupe(true));

// Index by EIN — the pairing that always holds.
Map<String, Nonprofit> byEin = result.getOrganizations().stream()
        .collect(Collectors.toMap(Nonprofit::getEin, org -> org, (first, second) -> first));
```

The caller's list is copied before validation, so a list mutated from another thread cannot change what was validated into something else by the time it is serialized.

## Usage and billing cycle

`nonprofit_check_count`, surfaced as `getCheckCount()`, is the number of checks your account has consumed **so far in the current billing cycle**, including the request that returned it. It resets when a new cycle starts.

It is not the size of the request you just made. A bulk call for five EINs does not return `5`.

```java
SingleCheckResult before = client.nonprofits().check(ein);
BulkCheckResult after = client.nonprofits().checkBulk(eins);

after.getCheckCount();                            // cycle total, e.g. 1284
after.getCheckCount() - before.getCheckCount();   // what these requests actually consumed
```

EINs with no matching record are not billed, so a delta can be smaller than the batch you sent. Read the number the API reports rather than reconstructing usage from your input.

## Inspecting source-specific findings

The API returns source fields flat on the organization (`pub78_*`, `bmf_*`, `ofac_*`, and the revocation fields). Read them directly, or use the grouped views — which copy fields 1:1 and derive nothing.

```java
import org.pactman.nonprofitcheckplus.Sources;

Nonprofit nonprofit = client.nonprofits().check("41-1787097").getNonprofit();

// IRS Publication 78
Pub78Source pub78 = Sources.pub78(nonprofit);
if (pub78 == null) {
    System.out.println("Publication 78 data was not returned for this organization.");
} else {
    System.out.println(pub78.getVerified());   // TRUE, FALSE, or null
    System.out.println(pub78.getMostRecent()); // date of the Pub 78 record
}

// IRS Business Master File
BmfSource bmf = Sources.bmf(nonprofit);

// IRS Automatic Revocation of Exemption
AroeSource aroe = Sources.aroe(nonprofit);

// OFAC Specially Designated Nationals
OfacSource ofac = Sources.ofac(nonprofit);
System.out.println(ofac.getStatus()); // a sentence describing the finding
```

Each view is `null` only when the API returned **no data at all** for that source. That keeps _"the source was not returned"_ distinct from an explicit negative such as `pub78_verified: false`.

**On OFAC:** the API returns `ofac_status` as prose, not a boolean. This SDK deliberately does not expose a `hasOfacMatch()` flag, because deriving one would mean pattern-matching English that could be reworded at any time. Read the status, or route it to a reviewer.

## Response models and raw data

Wire field names are preserved exactly, so the API reference and your code use the same names — there is no rename table to keep in sync.

Unknown fields never break deserialization. Anything the API adds in a future version is readable through the same object:

```java
nonprofit.get("some_future_field"); // readable without an SDK upgrade
nonprofit.toMap();                  // every field, in the order the API returned them
nonprofit.toJson();                 // re-serialized, unmodified
result.getRaw();                    // the complete envelope
```

`null` and `false` are preserved as distinct values wherever the API distinguishes them, and **an absent field is distinguishable from one returned as null**:

```java
nonprofit.has("bmf_status");        // did the API send this field at all?
nonprofit.getBmfStatus();           // null for both "absent" and "sent as null"
```

That distinction is load-bearing for this API: "no data for this source" and "this source says null" route differently, and collapsing them loses a finding.

## EIN validation and normalization

```java
import org.pactman.nonprofitcheckplus.Ein;

Ein.normalize("41-1787097"); // "411787097"
Ein.normalize("411787097");  // "411787097"
Ein.isValid("4117870");      // false
```

Accepted: nine digits, with or without the conventional hyphen after the two-digit prefix, ignoring surrounding whitespace. Rejected: letters, other punctuation, wrong digit counts, empty and null values. No IRS prefix rules are applied.

Bulk validation reports every failure at once, by index:

```java
try {
    client.nonprofits().checkBulk(List.of("411787097", "nope", "1234"));
} catch (PactmanValidationException failure) {
    for (ValidationIssue issue : failure.issues()) {
        System.err.println(issue.index() + " " + issue.value() + " " + issue.message());
    }
}
```

> Formatting validation confirms only that a value is shaped like an EIN. It says nothing about tax-exempt status, identity, eligibility, or good standing.

## Error handling

Every failure is a `PactmanException` with a stable `category()` and an `origin()` of `LOCAL` or `API`. Branch on the class or the category — never on message text.

All of them are unchecked, so a lookup composes inside a stream or a lambda without a wrapper.

```java
try {
    client.nonprofits().check(ein);
} catch (PactmanValidationException failure) {
    // Bad input. Nothing was sent.
} catch (PactmanAuthenticationException failure) {
    // The key was rejected.
} catch (PactmanRateLimitException failure) {
    System.out.println(failure.retryAfterSeconds());
} catch (PactmanTimeoutException failure) {
    System.out.println(failure.timeoutMs());
} catch (PactmanApiException failure) {
    System.out.println(failure.status() + " " + failure.requestId() + " " + failure.apiErrors());
}
```

| Class                            | Category         | Origin | Raised for                          |
| -------------------------------- | ---------------- | ------ | ----------------------------------- |
| `PactmanConfigurationException`  | `configuration`  | local  | Unusable client options             |
| `PactmanValidationException`     | `validation`     | local  | Input rejected before sending       |
| `PactmanBadRequestException`     | `bad_request`    | api    | HTTP 400                            |
| `PactmanAuthenticationException` | `authentication` | api    | HTTP 401                            |
| `PactmanAuthorizationException`  | `authorization`  | api    | HTTP 403                            |
| `PactmanNotFoundException`       | `not_found`      | api    | HTTP 404                            |
| `PactmanRateLimitException`      | `rate_limit`     | api    | HTTP 429                            |
| `PactmanServerException`         | `server`         | api    | HTTP 5xx                            |
| `PactmanApiException`            | `api`            | api    | Any other unexpected response       |
| `PactmanTimeoutException`        | `timeout`        | local  | Exceeded the configured timeout     |
| `PactmanNetworkException`        | `network`        | local  | No response, or caller cancellation |

API exceptions carry `status()`, `apiCode()`, `apiMessage()`, `apiErrors()`, `requestId()`, `retryAfterSeconds()`, `attempts()`, and `raw()`. When a body cannot be deserialized, the metadata is still preserved and `raw()` holds what the server actually sent.

`toMap()` on any exception gives a redacted, loggable view.

## Timeouts and cancellation

The default timeout is **30 seconds** per attempt, published as `PactmanClientOptions.DEFAULT_TIMEOUT_MS`. It is always finite — there is no way to disable it.

```java
PactmanClient client = new PactmanClient(PactmanClientOptions.builder()
        .apiKey(apiKey)
        .timeoutMs(10_000)
        .build());

// Or per request.
client.nonprofits().check(ein, new RequestOptions().timeoutMs(5_000));
```

There is no cancellation-token parameter. Java already has two ways to say "stop", and the SDK honors both:

```java
// A blocking call stops when its thread is interrupted.
worker.interrupt();

// An async call stops when its future is cancelled.
future.cancel(true);
```

Either one surfaces as `PactmanNetworkException` — nothing expired, someone asked for the work to stop — and it stops the in-flight request *and* any planned retries.

## Asynchronous calls

Every method has an `Async` form returning a `CompletableFuture`:

```java
CompletableFuture<SingleCheckResult> pending = client.nonprofits().checkAsync("41-1787097");
CompletableFuture<BulkCheckResult> batch = client.nonprofits().checkBulkAsync(eins);

CompletableFuture.allOf(pending, batch).join();
```

The work runs on a pool the client owns, not the common `ForkJoinPool` — a batch of blocking lookups there would starve every parallel stream in your application. The threads are daemons and retire after 60 seconds idle. Cancelling the returned future really interrupts the work rather than abandoning a request that keeps running invisibly.

Exceptions arrive wrapped in `ExecutionException`; `getCause()` is the same `PactmanException` the blocking call would have thrown.

## Retries

Enabled by default: up to **2 retries** (3 attempts total), exponential backoff from 500ms with full jitter, capped at 8 seconds per delay.

```java
PactmanClient client = new PactmanClient(PactmanClientOptions.builder()
        .apiKey(apiKey)
        .retry(RetryOptions.builder()
                .maxRetries(3)
                .initialDelayMs(500)
                .maxDelayMs(8_000)
                .backoffFactor(2)
                .jitter(true)
                .retryableStatuses(Set.of(429, 500, 502, 503, 504))
                .respectRetryAfter(true)
                .build())
        .build());

// Disable entirely.
PactmanClientOptions.builder().apiKey(apiKey).retry(RetryOptions.disabled()).build();

// Or override per request. A per-request policy replaces the client's outright,
// so start from the client's own when you mean to change one setting.
client.nonprofits().check(ein, new RequestOptions()
        .retry(client.retry().toBuilder().maxRetries(0).build()));
```

Retried: 429, 500, 502, 503, 504, and transient network failures. **Never** retried: 400, 401, 403, 404, and local validation errors — regardless of `retryableStatuses`. A valid `Retry-After` always takes precedence over computed backoff, including when it exceeds `maxDelayMs`.

## Rate limits

The API returns HTTP 429 when you exceed your limit. The SDK maps that to `PactmanRateLimitException` and exposes `retryAfterSeconds()`.

```java
try {
    client.nonprofits().check(ein);
} catch (PactmanRateLimitException failure) {
    System.out.println("Retry in " + failure.retryAfterSeconds() + " seconds");
}
```

With retries enabled, a 429 is retried automatically after the server's `Retry-After`, falling back to backoff when none is sent.

An optional client-side ceiling is available and off by default:

```java
PactmanClientOptions.builder().apiKey(apiKey).maxRequestsPerSecond(3).build();
```

Server-provided limits are authoritative and may vary by account and endpoint; treat this as a courtesy throttle, not a guarantee. For bulk workloads, prefer the bulk endpoint over concurrent single checks, and keep your own concurrency bounded — the SDK does not queue on your behalf.

## Client lifecycle and thread safety

`PactmanClient` is thread-safe and designed to be long-lived. **Build one per application and share it.** A client per request throws away connection reuse, and gives each caller its own throttle state — which is not a throttle at all.

```java
@Bean
PactmanClient pactmanClient(@Value("${pactman.api-key}") String apiKey) {
    return new PactmanClient(apiKey);
}
```

`close()` shuts down the async thread pool. That pool is created on first async use, so a client that only ever makes blocking calls holds no threads and needs no closing.

## Supplying your own HTTP client

Pass an `HttpClient` to share your application's connection pool, proxy or TLS configuration:

```java
PactmanClientOptions.builder()
        .apiKey(apiKey)
        .httpClient(HttpClient.newBuilder().proxy(proxySelector).build())
        .build();
```

For a test double, instrumentation, or a transport that is not `java.net.http` at all, implement `HttpExchange` — one method, one exchange. Timeouts, retries and rate limiting still apply above it:

```java
PactmanClientOptions.builder()
        .apiKey(apiKey)
        .httpExchange(request -> CompletableFuture.completedFuture(cannedResponse))
        .build();
```

## Security

- Load the key from an environment variable or secret manager. Never commit it.
- **Server-side only.** Authenticated calls from a client-side artifact expose the key to anyone who decompiles it.
- The key is redacted from every diagnostic surface: exception messages, `toMap()`, `client.toString()`, and `client.toMap()`.
- A default or per-request header named `Authorization` is dropped, so it cannot be sent alongside the real credential.
- Rotate the key if it is ever printed, logged, or committed.
- Nonprofit records may be subject to your own retention and privacy obligations. Storing responses is your call, not the SDK's.

## What this SDK does not tell you

The SDK exposes what the API returns and nothing more. It deliberately provides **no** composite `approved`, `eligible`, or `safe` verdict, and no boolean summarizing a source that the API does not itself express as a boolean.

A successful check is data, not a decision. Whether an organization qualifies for a grant, a donation, a match, or a partnership is a determination for your own legal, compliance, grantmaking, and risk policy.

## API reference

**Client** — `new PactmanClient(String apiKey)` or `new PactmanClient(PactmanClientOptions)`

| Option                 | Type                    | Default      |                                                     |
| ---------------------- | ----------------------- | ------------ | --------------------------------------------------- |
| `apiKey`               | `String`                | —            | **Required.**                                       |
| `environment`          | `PactmanEnvironment`    | `PRODUCTION` | The only named environment.                         |
| `baseUrl`              | `String`                | —            | Overrides `environment`. Validated locally.         |
| `timeoutMs`            | `long`                  | `30000`      | Per attempt. Always finite.                         |
| `retry`                | `RetryOptions`          | 2 retries    | `RetryOptions.disabled()` to switch off.            |
| `maxRequestsPerSecond` | `double`                | off          | Client-side courtesy throttle.                      |
| `defaultHeader`        | `String, String`        | none         | Cannot override `Authorization`.                    |
| `httpClient`           | `HttpClient`            | built        | Share your application's pool.                      |
| `httpExchange`         | `HttpExchange`          | JDK client   | Replaces the HTTP layer entirely.                   |

**Lookups** — `client.nonprofits()`

| Method                                              | Returns                            |
| --------------------------------------------------- | ---------------------------------- |
| `check(String ein[, RequestOptions])`               | `SingleCheckResult`                |
| `checkAsync(String ein[, RequestOptions])`          | `CompletableFuture<SingleCheckResult>` |
| `checkBulk(List<String>[, BulkRequestOptions])`     | `BulkCheckResult`                  |
| `checkBulkAsync(List<String>[, BulkRequestOptions])`| `CompletableFuture<BulkCheckResult>` |

**Endpoints** — `Endpoints.SINGLE_CHECK_PATH`, `Endpoints.BULK_CHECK_PATH`, `Endpoints.MAX_BULK_EINS`

**EINs** — `Ein.normalize`, `Ein.normalizeAll`, `Ein.isValid`, `Ein.EIN_LENGTH`

**Sources** — `Sources.pub78`, `Sources.bmf`, `Sources.aroe`, `Sources.ofac`

**Version** — `SdkVersion.VERSION`, `SdkVersion.PACKAGE_NAME`, `SdkVersion.userAgent()`

## Examples

Runnable examples live in [`examples/`](./examples). Each is self-contained and reads its key from `PACTMAN_API_KEY`.

```bash
# Every example, against the bundled fixture API. No key, no network.
# This also runs as part of `mvn verify`, so a stale example fails the build.
mvn -q verify

# Install the SDK locally once, then run examples individually.
mvn -q -DskipTests install
mvn -q -pl examples exec:java -Dexec.args="--list"
PACTMAN_API_KEY=... mvn -q -pl examples exec:java -Dexec.args="ex-01"
```

Point any example at a different host with `PACTMAN_BASE_URL`.

Examples that need a record or a response a live API will not produce on request — a revoked exemption, an OFAC match, an HTTP 429, a field newer than this SDK — run against a bundled fixture server instead of production.

| Group                        |                                                                     |
| ---------------------------- | ------------------------------------------------------------------- |
| Getting started              | `ex-01` to `ex-03` — client setup, EIN normalization, identity lookup |
| Comparing against the record | `ex-04`, `ex-05` — name comparison, address validation                |
| Reading the sources          | `ex-06` to `ex-14` — BMF, Pub 78, revocation, OFAC, conflicts, freshness |
| Errors and edge cases        | `ex-15`, `ex-16`, `ex-22` to `ex-25` — malformed input, not found, rate limits, retries, timeouts, forward compatibility |
| Bulk                         | `ex-17` to `ex-21` — screening, ordering, partial success, limits, usage |
| End-to-end workflows         | `ex-26` to `ex-30` — onboarding, DAF screening, CRM enrichment, re-checks |

## Building from source

```bash
mvn test               # unit tests only
mvn verify             # tests, plus every example against the fixture API
mvn -Prelease package  # jar, sources, javadoc
```

The reactor has three modules. Only `sdk` is published; `devtools` and
`examples` are build-time only.

| Module     |                                                                     |
| ---------- | ------------------------------------------------------------------- |
| `sdk`      | The published artifact and its tests                                 |
| `devtools` | Fixture records, a stand-in API, and the response-drift engine       |
| `examples` | The runnable examples                                                |

## Checking a live deployment

The typed accessors promise a shape. `sdk/src/main/resources/.../response-contract.json`
states that promise in a token vocabulary, and `smoke-live` holds a real
deployment against it — the one check that can notice the API disagreeing with
what this package tells its users.

```bash
mvn -q -DskipTests install

# Does the API still match what this package promises?
PACTMAN_API_KEY=... mvn -q -pl devtools exec:java \
    -Dexec.args="smoke-live --ein 41-1787097"

# Has it moved since we last looked? Record once, compare later.
PACTMAN_API_KEY=... mvn -q -pl devtools exec:java \
    -Dexec.args="smoke-live --record baseline.json"
PACTMAN_API_KEY=... mvn -q -pl devtools exec:java \
    -Dexec.args="smoke-live --baseline baseline.json"

# The stand-in API, for pointing your own application at.
mvn -q -pl devtools exec:java -Dexec.args="mock"
```

A baseline records shapes only — path, JSON type and value format, never a
value — so it is safe to commit and a diff of it is safe to print. It is
compared with nullability and reachability excused, because a recording is one
organization's response on one afternoon and much of what separates it from
today's run is a different subject rather than the API changing.

`smoke-live` spends real quota against a real key, so it is deliberately not
part of `mvn verify`.

No local Maven? The build runs unchanged in a container:

```bash
docker run --rm -v "$PWD":/work -w /work maven:3.9-eclipse-temurin-17 mvn test
```

## Support

- API documentation: <https://pactman.org/nonprofitcheckplus-api/docs>
- Issues: <https://github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks/issues>

## License

MIT — see [LICENSE](../LICENSE).
