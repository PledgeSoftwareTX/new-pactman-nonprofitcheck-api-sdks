# Pactman.NonprofitCheckPlus

Official .NET SDK for the **Pactman Nonprofit Check Plus API** — verify US nonprofits by EIN against IRS Business Master File, Publication 78, Automatic Revocation of Exemption and OFAC data.

[![NuGet](https://img.shields.io/nuget/v/Pactman.NonprofitCheckPlus.svg)](https://www.nuget.org/packages/Pactman.NonprofitCheckPlus)

One `PactmanClient`, two calls, a typed model that never hides a field the API sent.

```csharp
using var client = new PactmanClient(Environment.GetEnvironmentVariable("PACTMAN_API_KEY"));

var result = await client.Nonprofits.CheckAsync("41-1787097");

Console.WriteLine(result.Nonprofit?.OrganizationName);   // EXAMPLE NONPROFIT
Console.WriteLine(result.Nonprofit?.Pub78Verified);      // True
```

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
- [Bringing your own HttpClient](#bringing-your-own-httpclient)
- [Dependency injection](#dependency-injection)
- [.NET-specific notes](#net-specific-notes)
- [Security](#security)
- [What this SDK does not tell you](#what-this-sdk-does-not-tell-you)
- [API reference](#api-reference)
- [Examples](#examples)
- [Development](#development)
- [Support](#support)
- [License](#license)

## Requirements

- **.NET 8.0 or later**, or any runtime supporting **.NET Standard 2.0** — .NET Framework 4.6.2+, Mono, Unity, Xamarin.
- A Pactman API key. Register at [pactman.org](https://pactman.org) and generate one from your developer dashboard.

The package ships two build legs. Modern .NET loads `lib/net8.0`; everything else loads `lib/netstandard2.0`, which pulls in `System.Text.Json` as its only dependency.

## Installation

```bash
dotnet add package Pactman.NonprofitCheckPlus
```

Or in your `.csproj`:

```xml
<PackageReference Include="Pactman.NonprofitCheckPlus" Version="1.0.0" />
```

## Configuring your API key

The key is a private, server-side credential. Load it from the environment or a secret manager — never a literal, never a file you commit, never anything shipped to a browser or a mobile app.

```bash
# .env, or your host's environment settings — excluded from version control
PACTMAN_API_KEY=your_key_here
```

```csharp
var apiKey = Environment.GetEnvironmentVariable("PACTMAN_API_KEY");
```

In ASP.NET Core, `IConfiguration` reads it from user secrets in development and from the environment or your key vault in production:

```csharp
var apiKey = builder.Configuration["Pactman:ApiKey"];
```

A missing or blank key throws `PactmanConfigurationException` at construction, not on the first request.

## Quick start

```csharp
using Pactman.NonprofitCheckPlus;
using Pactman.NonprofitCheckPlus.Exceptions;

using var client = new PactmanClient(Environment.GetEnvironmentVariable("PACTMAN_API_KEY"));

try
{
    var result = await client.Nonprofits.CheckAsync("41-1787097");

    if (result.Nonprofit is null)
    {
        Console.WriteLine("No record for that EIN.");
        return;
    }

    Console.WriteLine(result.Nonprofit.OrganizationName);
    Console.WriteLine(result.Nonprofit.Pub78Verified);
    Console.WriteLine(result.Nonprofit.BmfStatus);
    Console.WriteLine(result.Nonprofit.OfacStatus);
}
catch (PactmanValidationException error)
{
    // Bad input. Nothing was sent, and nothing was billed.
    Console.Error.WriteLine(error.Message);
}
catch (PactmanException error)
{
    Console.Error.WriteLine($"{error.Category}: {error.Message}");
}
```

Build **one client per process and share it.** It is safe to use concurrently, and each instance carries its own connection pool and throttle state — constructing one per request throws both away and leaks sockets through `TIME_WAIT`.

## Environment and base URL

The client targets production by default. Nothing else in the package contains a Pactman host.

```csharp
using var client = new PactmanClient(new PactmanClientOptions
{
    ApiKey = apiKey,
    Environment = PactmanEnvironment.Production,   // the default
});
```

To point at a mock server, a proxy, or a host Pactman gave you directly, set `BaseUrl`. It overrides `Environment`, and `client.Environment` then reads `null`:

```csharp
using var client = new PactmanClient(new PactmanClientOptions
{
    ApiKey = apiKey,
    BaseUrl = "http://127.0.0.1:8787",
});
```

A base URL is normalized to `scheme://authority[/path]` with no trailing slash, and validated at construction — a malformed one, a non-HTTP scheme, or a blank string throws `PactmanConfigurationException` rather than quietly falling back to production.

## Single check

```csharp
var result = await client.Nonprofits.CheckAsync("41-1787097");
```

The EIN is normalized and validated locally first, so `"41-1787097"` and `"411787097"` are the same call and a malformed EIN throws before anything is sent.

`result.Nonprofit` is `null` when the API has no record — that is a normal answer, not an error.

Per-request overrides:

```csharp
var options = new RequestOptions { Timeout = TimeSpan.FromSeconds(5) };
options.Headers["X-Correlation-Id"] = correlationId;

var result = await client.Nonprofits.CheckAsync("41-1787097", options, cancellationToken);
```

## Bulk check

Up to `Endpoints.MaxBulkEins` (50) EINs per request:

```csharp
var result = await client.Nonprofits.CheckBulkAsync(new[] { "41-1787097", "04-2103594" });

foreach (var organization in result.Organizations)
{
    Console.WriteLine($"{organization.Ein}: {organization.OrganizationName}");
}

Console.WriteLine(string.Join(", ", result.NotFoundEins));
```

Three things about bulk that catch people out:

**The response is a set, not a row-for-row answer.** The API matches by set membership, so the order you sent is not the order you get back, and a repeated EIN comes back once. Never pair `Organizations` positionally with your input — index it:

```csharp
var byEin = result.ByEin();

if (byEin.TryGetValue(Ein.Normalize(inputEin), out var organization))
{
    // ...
}
```

Keys are the normalized nine-digit form, so look up with `Ein.Normalize(...)` rather than the hyphenated string you may have supplied.

**Missing EINs are a success, not a failure.** They arrive as HTTP 200 with the values in `NotFoundEins`, collected from the envelope's `errors`.

**Duplicates are sent as supplied.** Each one consumes quota, and silently dropping them would misreport what was checked. Opt in when you want them collapsed:

```csharp
await client.Nonprofits.CheckBulkAsync(eins, new BulkRequestOptions { Dedupe = true });
```

Over the limit, empty, or containing a malformed EIN all throw `PactmanValidationException` before anything is sent. The SDK does not chunk automatically — batching is your call, because it decides how much quota a call spends.

## Usage and billing cycle

Every result carries `CheckCount`, the envelope's `nonprofit_check_count`: checks consumed so far in the **current billing cycle**, including this request, resetting each cycle.

```csharp
Console.WriteLine($"Checks used this cycle: {result.CheckCount}");
```

It is not the size of this request. Take the delta between two responses if that is what you need.

## Inspecting source-specific findings

Source fields are flat on the organization, prefixed by source. `Sources` groups them:

```csharp
using Pactman.NonprofitCheckPlus;

var organization = result.Nonprofit!;

var pub78 = organization.Pub78();   // or Sources.Pub78(organization)
var bmf   = organization.Bmf();
var aroe  = organization.Aroe();
var ofac  = organization.Ofac();

if (pub78 is not null)
{
    Console.WriteLine(pub78.Verified);
    Console.WriteLine(pub78.Indicator);

    foreach (var entry in pub78.OrganizationTypes)
    {
        Console.WriteLine($"{entry.DeductibilityStatusDescription}: {entry.DeductibilityLimitation}");
    }
}
```

These are **projections, not derivations.** Every key is copied 1:1 from a field the API returned. Nothing computes an "approved", "eligible" or "safe" verdict, and nothing infers a value from another field.

Each accessor returns `null` when the API returned no data at all for that source. That keeps "the source was not returned" distinguishable from an explicit negative such as `Verified == false`.

`OfacStatus` is prose, not a flag. The API does not return a boolean match indicator, and this SDK does not invent one by matching on the wording.

## Response models and raw data

`Nonprofit`, the four source views and `OrganizationType` all extend `DataObject`, an immutable view over the decoded JSON. Typed properties are conveniences over the wire fields, not a separate deserialization — so a field a future API version adds stays readable without an SDK upgrade and without a deserialization failure.

```csharp
organization.OrganizationName;                  // typed, autocompleted
organization.GetString("organization_name");    // by wire name
organization["some_future_field"];              // raw JsonElement?, or null
organization.Get<MyShape>("some_future_field"); // deserialized
```

**`Has()` answers "did the API return this field?"** — including when it returned it as JSON `null`. That distinction is load-bearing for this API: "no data for this source" and "this source says null" route differently, and collapsing them loses a finding.

```csharp
organization.Has("address_line2");  // true even when address_line2 is null
organization.AddressLine2;          // null either way
```

Everything is also available unmodified:

```csharp
organization.ToJson();          // re-serialized, in the order the API sent it
organization.ToDictionary();     // plain CLR values, for structured logging
result.Raw.Envelope;             // the whole envelope as a JsonElement
result.Raw.Text;                 // the raw text, when the body was not JSON
```

A server that answers 200 with an HTML error page leaves that page in `Raw.Text` rather than having it discarded — an unparseable body is still evidence.

## EIN validation and normalization

```csharp
Ein.Normalize("41-1787097");    // "411787097"
Ein.IsValid("nope");            // false — never throws
Ein.NormalizeMany(eins);        // reports every failure at once
```

Formatting validation only. Passing these checks says nothing about whether an organization is tax-exempt, in good standing, or eligible for anything — only that the value is shaped like an EIN.

`NormalizeMany` reports every bad item in one exception, each `ValidationIssue` naming its index and original value, so a caller fixes a whole batch in one pass instead of one item per round trip.

**Watch for EINs that have been through a numeric type.** `042103594` read as an `int` — from a spreadsheet column, a JSON number, a database `bigint` — is `42103594`: the leading zero is gone and the value is a different EIN. Keep EINs as strings end to end.

## Error handling

Every exception the SDK throws derives from `PactmanException` and carries a stable `Category` and `Origin`. Branch on the type or the category — never on message text.

```csharp
try
{
    var result = await client.Nonprofits.CheckAsync(ein);
}
catch (PactmanValidationException error)      // local; nothing was sent
{
    foreach (var issue in error.Issues)
    {
        Console.Error.WriteLine($"[{issue.Index}] {issue.Message}");
    }
}
catch (PactmanRateLimitException error)       // 429
{
    await Task.Delay(error.RetryAfter ?? TimeSpan.FromSeconds(30));
}
catch (PactmanAuthenticationException)        // 401 — the key is bad; do not retry
{
    throw;
}
catch (PactmanApiException error)             // any other non-2xx
{
    logger.LogError("Pactman {Status} {RequestId}: {Message}",
        error.Status, error.RequestId, error.Message);
}
catch (PactmanTimeoutException error)         // our deadline expired
{
    logger.LogWarning("Timed out after {Timeout} on attempt {Attempts}",
        error.Timeout, error.Attempts);
}
catch (PactmanNetworkException error)         // no HTTP response at all
{
    logger.LogWarning(error, "Could not reach Pactman");
}
```

| Exception                          | Category         | Origin  | When |
| ---------------------------------- | ---------------- | ------- | ---- |
| `PactmanConfigurationException`     | `Configuration`  | `Local` | Unusable client options. |
| `PactmanValidationException`        | `Validation`     | `Local` | Bad input; nothing was sent. |
| `PactmanBadRequestException`        | `BadRequest`     | `Api`   | HTTP 400. |
| `PactmanAuthenticationException`    | `Authentication` | `Api`   | HTTP 401. |
| `PactmanAuthorizationException`     | `Authorization`  | `Api`   | HTTP 403. |
| `PactmanNotFoundException`          | `NotFound`       | `Api`   | HTTP 404. |
| `PactmanRateLimitException`         | `RateLimit`      | `Api`   | HTTP 429. |
| `PactmanServerException`            | `Server`         | `Api`   | HTTP 5xx. |
| `PactmanApiException`               | `Api`            | `Api`   | Any other non-2xx. |
| `PactmanTimeoutException`           | `Timeout`        | `Local` | The SDK's deadline expired. |
| `PactmanNetworkException`           | `Network`        | `Local` | No HTTP response was produced. |

`Category.ToWireValue()` returns the same string the Node, Python and PHP SDKs log for the same failure, so one dashboard covers all four.

Every API exception carries `Status`, `ApiMessage`, `ApiCode`, `ApiErrors`, `RequestId`, `RetryAfter`, `Raw` and `Attempts`. `error.ToDictionary()` renders all of it for structured logging, with the API key nowhere in it.

Item-level failures arrive on **successful** responses too — a bulk request where some EINs miss is a 200 with entries in `result.Errors`.

## Timeouts and cancellation

`Timeout` is the deadline for **one attempt**, defaulting to 30 seconds. A request that retries twice can take up to three times that.

```csharp
using var client = new PactmanClient(new PactmanClientOptions
{
    ApiKey = apiKey,
    Timeout = TimeSpan.FromSeconds(10),
});

await client.Nonprofits.CheckAsync(ein, new RequestOptions { Timeout = TimeSpan.FromSeconds(3) });
```

To bound the call **as a whole**, retries included, pass a `CancellationToken`:

```csharp
using var budget = new CancellationTokenSource(TimeSpan.FromSeconds(20));

var result = await client.Nonprofits.CheckAsync(ein, cancellationToken: budget.Token);
```

The two stay distinguishable on purpose. An expired SDK deadline throws `PactmanTimeoutException`; a token *you* cancelled throws `OperationCanceledException`, untranslated. "I gave up" never arrives dressed as "the API was too slow".

There is no way to disable the timeout. A zero or negative one throws at construction.

## Retries

Two retries by default, with full-jitter exponential backoff.

```csharp
using var client = new PactmanClient(new PactmanClientOptions
{
    ApiKey = apiKey,
    Retry = new RetryOptions
    {
        MaxRetries = 4,
        InitialDelay = TimeSpan.FromMilliseconds(250),
        MaxDelay = TimeSpan.FromSeconds(10),
        BackoffFactor = 2.0,
        Jitter = true,
        RetryableStatuses = new[] { 429, 500, 502, 503, 504 },
        RespectRetryAfter = true,
    },
});
```

Every property carries the SDK default, so `new RetryOptions { MaxRetries = 5 }` is a complete policy rather than a patch. To adjust one setting, start from the policy in force:

```csharp
await client.Nonprofits.CheckAsync(ein, new RequestOptions
{
    Retry = client.Retry with { MaxRetries = 5 },
});

await client.Nonprofits.CheckAsync(ein, new RequestOptions { Retry = RetryOptions.None });
```

Values are validated on construction **and on every `with`**, so an unusable policy fails at the assignment rather than mid-flight on a retry.

**400, 401, 403 and 404 are never retried,** whatever `RetryableStatuses` contains — they will not become a different answer. Timeouts and connection failures are retried. A valid `Retry-After` wins outright over computed backoff, even when it exceeds `MaxDelay`.

Full jitter randomizes each delay across `[0, computed]` rather than around it, so clients that failed together do not retry in lockstep.

## Rate limits

The server's limits are authoritative and may change. The SDK does not guess at them, and the ceiling below is off by default:

```csharp
using var client = new PactmanClient(new PactmanClientOptions
{
    ApiKey = apiKey,
    MaxRequestsPerSecond = 5,
});
```

When set, outbound requests — retries included — are spaced to that interval. The schedule is claimed under a lock, so a client shared across threads still honors the ceiling in aggregate rather than per thread.

This is a courtesy throttle in front of a server-side limit, not a replacement for handling `PactmanRateLimitException`.

## Bringing your own HttpClient

Leave `HttpClient` unset and the client creates and owns one, which `Dispose` tears down. Supply your own — a shared pool, a proxy, pinned certificates, a recording handler in tests — and it is borrowed, not owned:

```csharp
var handler = new HttpClientHandler
{
    Proxy = new WebProxy("http://proxy.internal:3128"),
    AutomaticDecompression = DecompressionMethods.All,
};

using var client = new PactmanClient(new PactmanClientOptions
{
    ApiKey = apiKey,
    HttpClient = new HttpClient(handler),
    DisposeHttpClient = true,      // this one is ours to close
});
```

The SDK sets no `HttpClient.Timeout` on a borrowed client: per-attempt deadlines are enforced with a cancellation token, so your client's own timeout stays whatever you set it to. Set it to `Timeout.InfiniteTimeSpan` if you want this SDK's timeout to be the only one in play.

## Dependency injection

Register the client as a **singleton** and hand it an `IHttpClientFactory` client, which handles pooling and DNS refresh:

```csharp
builder.Services.AddHttpClient("pactman");

builder.Services.AddSingleton(provider => new PactmanClient(new PactmanClientOptions
{
    ApiKey = provider.GetRequiredService<IConfiguration>()["Pactman:ApiKey"],
    HttpClient = provider.GetRequiredService<IHttpClientFactory>().CreateClient("pactman"),
    // DisposeHttpClient stays off: the factory owns that client.
}));
```

Then inject `PactmanClient` wherever you need it.

## .NET-specific notes

**Async only, and never block on it.** `CheckAsync` and `CheckBulkAsync` are the whole surface. There is no synchronous overload, deliberately: `.Result` or `.GetAwaiter().GetResult()` on a request that retries is how a thread-pool starvation incident starts.

**Nullable reference types are annotated throughout.** Enable `<Nullable>enable</Nullable>` and the compiler will tell you which fields the API may omit — which is nearly all of them.

**Thread safety.** One `PactmanClient` is safe for concurrent use across threads and requests. `Nonprofit` and every model are immutable.

**`Has()` versus `null`.** A model reports whether the API returned a field, including when it returned it as `null`. See [Response models and raw data](#response-models-and-raw-data).

**`ConfigureAwait(false)` is used throughout the library,** so the SDK never captures your synchronization context.

## Security

- Load the key from an environment variable or secret manager. Never commit it.
- **Server-side only.** The key must not reach an end user's device.
- The key is redacted from every diagnostic surface: exception messages, `error.ToDictionary()`, `client.ToDictionary()`, `client.ToString()`, and anything that serializes those. It is held in a delegate rather than a field, so no property, no serializer and no `ToString()` reaches it.
- Rotate the key if it is ever printed, logged, or committed.
- The `User-Agent` is sanitized before it is sent — `RuntimeInformation.OSDescription` is free text and is the whole `uname` line on Linux, newlines included, which would otherwise be a header-injection seam in every request.
- Nonprofit records may be subject to your own retention and privacy obligations. Storing responses is your call, not the SDK's.

## What this SDK does not tell you

The SDK exposes what the API returns and nothing more. It deliberately provides **no** composite `Approved`, `Eligible`, or `Safe` verdict, and no boolean summarizing a source that the API does not itself express as a boolean.

A successful check is data, not a decision. Whether an organization qualifies for a grant, a donation, a match, or a partnership is a determination for your own legal, compliance, grantmaking, and risk policy.

## API reference

**Client** — `new PactmanClient(apiKey)` or `new PactmanClient(PactmanClientOptions)`

| Option                 | Type                            | Default      | |
| ---------------------- | ------------------------------- | ------------ | - |
| `ApiKey`               | `string`                        | —            | **Required.** |
| `Environment`          | `PactmanEnvironment?`           | `Production` | Named environment. |
| `BaseUrl`              | `string?`                       | —            | Explicit host; overrides `Environment`. |
| `Timeout`              | `TimeSpan?`                     | `30s`        | Per-attempt timeout. |
| `Retry`                | `RetryOptions?`                 | 2 retries    | Retry policy. |
| `MaxRequestsPerSecond` | `double?`                       | off          | Optional client-side throttle. |
| `DefaultHeaders`       | `IDictionary<string, string>`   | empty        | Extra headers; cannot override `Authorization`. |
| `HttpClient`           | `HttpClient?`                   | SDK-owned    | Where to send through. |
| `DisposeHttpClient`    | `bool`                          | `false`      | Dispose a supplied client with this one. |

Accessors: `client.Nonprofits`, `client.BaseUrl`, `client.Environment`, `client.Timeout`, `client.Retry`, `client.ToDictionary()`.

**Methods**

- `client.Nonprofits.CheckAsync(string ein, RequestOptions? options = null, CancellationToken ct = default)` → `Task<SingleCheckResult>`
- `client.Nonprofits.CheckBulkAsync(IEnumerable<string> eins, BulkRequestOptions? options = null, CancellationToken ct = default)` → `Task<BulkCheckResult>`

**Results** — `SingleCheckResult` and `BulkCheckResult` share `CheckCount`, `TimeTakenMs`, `Errors`, `RequestId`, `Status` and `Raw`. `SingleCheckResult` adds `Nonprofit`; `BulkCheckResult` adds `Organizations`, `NotFoundEins` and `ByEin()`.

**Models** — `Nonprofit`, `Pub78Source`, `BmfSource`, `AroeSource`, `OfacSource` and `OrganizationType` all extend `DataObject`: `Has()`, `Get()`, `Get<T>()`, `GetString()`, `GetBoolean()`, `GetDouble()`, `GetInt32()`, `GetElement()`, the `this[string]` indexer, `FieldNames`, `Count`, iteration, `ToDictionary()` and `ToJson()`.

**Helpers** — `Ein.Normalize()`, `Ein.NormalizeMany()`, `Ein.IsValid()`, `Sources.Pub78()`, `Sources.Bmf()`, `Sources.Aroe()`, `Sources.Ofac()` (each also an extension method), `PactmanEnvironments.Supported()`, `PactmanEnvironments.BaseUrl()`, `PactmanException.IsPactmanError()`, `ErrorCategories.ToWireValue()`

**Constants** — `Endpoints.MaxBulkEins`, `Endpoints.SingleCheckPath`, `Endpoints.BulkCheckPath`, `ClientConfig.DefaultTimeout`, `Ein.Length`, `PactmanEnvironments.Default`, `SdkVersion.Version`, `RetryOptions.Default`, `RetryOptions.None`

Every public member carries XML documentation, shipped in the package, so editor hover documentation works without leaving your code.

## Examples

Thirty numbered examples plus three overviews cover secure setup, every source on the
response, each error and edge case, bulk semantics, and five end-to-end workflows. They
live in [examples/](./examples/), one class each, and
[examples/README.md](./examples/README.md) indexes them.

```bash
dotnet run --project examples/Pactman.NonprofitCheckPlus.Examples -- --list
PACTMAN_API_KEY=your_key dotnet run --project examples/Pactman.NonprofitCheckPlus.Examples -- ex-01
```

Examples that need an ordinary lookup run against production. Ones that need a response a
live API will not produce on request — a revoked exemption, an OFAC match, an HTTP 429, an
address that contradicts itself, a field newer than this SDK — start a bundled fixture
server and shut it down on the way out.

Run all of them against that fixture server, which is what CI does:

```bash
dotnet run --project scripts/Pactman.NonprofitCheckPlus.Tools -- examples-smoke
```

An example that stops working is a documentation bug, and this catches it on the push that
caused it.

## Development

```bash
dotnet restore
dotnet build                        # warnings are errors, XML docs included
dotnet test
dotnet format --verify-no-changes
dotnet pack src/Pactman.NonprofitCheckPlus/Pactman.NonprofitCheckPlus.csproj -c Release -o artifacts
```

Four development commands live in [scripts/](./scripts/):

```bash
cd dotnet

# Serve the fixture API so you can point anything at it.
dotnet run --project scripts/Pactman.NonprofitCheckPlus.Tools -- mock --port 8787

# Run every documented example against it. This is the CI gate.
dotnet run --project scripts/Pactman.NonprofitCheckPlus.Tools -- examples-smoke

# Check a live deployment against the contract and the recording.
dotnet run --project scripts/Pactman.NonprofitCheckPlus.Tools -- smoke-live

# Re-record the production baseline. Spends billable checks; commit the result.
dotnet run --project scripts/Pactman.NonprofitCheckPlus.Tools -- baseline-record

# Print the signature of any JSON response, or diff two of them.
dotnet run --project scripts/Pactman.NonprofitCheckPlus.Tools -- contract response.json
```

### The two documents

`src/Pactman.NonprofitCheckPlus/response-contract.json` is what this package **promises**
each response looks like — path, JSON type and value format, never a value.
`tests/ResponseContractTests.cs` holds it and the typed model in sync by feeding the model
a sentinel response built from the contract and checking that removing any one field
darkens exactly one property. A diff there is a deliberate change to what the SDK promises.

`src/Pactman.NonprofitCheckPlus/response-baseline.json` is what production **returned**,
recorded once and committed. It catches the API drifting at all — including in the fields
the contract deliberately leaves as a bare `string`, where the promise is too loose to
notice anything. A run never writes it: a baseline that rewrites itself agrees with the API
by construction and can never fail.

`smoke-live` checks a live deployment against both, and prints no value from any response.

### Versioning

The version lives in `Directory.Build.props` as `PactmanSdkVersion`; `SdkVersion.Version`
is held against it by a unit test, and the publish workflow independently checks both
against the git tag. Three-way agreement, or the release fails loudly instead of shipping
quietly. Releases are cut by pushing a `dotnet-v<version>` tag — see the SDK release
runbook.

## Support

- API documentation: <https://pactman.org/nonprofitcheckplus-api/docs>
- Issues: <https://github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks/issues>

## License

MIT — see [LICENSE](./LICENSE).
