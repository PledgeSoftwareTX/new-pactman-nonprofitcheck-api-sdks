# pactman-nonprofit-check-plus

Official Ruby SDK for the **Pactman Nonprofit Check Plus API**. Look up US nonprofits by EIN and read the IRS and OFAC findings behind the result.

- Models for every documented response field, with the raw payload always available
- Local EIN normalization and validation, so malformed input never costs a request
- A structured error hierarchy you rescue by class, never by parsing message strings
- Finite default timeout, bounded retries with jittered backoff, and `Retry-After` support
- No runtime dependencies — the standard library's `Net::HTTP` and `JSON`, nothing else

> **Server-side only.** Your API key is a private credential. Never embed it in anything that ships to an end user.

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
- [Threads and connections](#threads-and-connections)
- [Custom HTTP adapters](#custom-http-adapters)
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

- Ruby **3.3 or newer** (tested on 3.3, 3.4 and 4.0)
- A Pactman API key with Nonprofit Check access

## Installation

```bash
bundle add pactman-nonprofit-check-plus
```

```bash
gem install pactman-nonprofit-check-plus
```

```ruby
require "pactman/nonprofit_check_plus"
```

Under Bundler, `Bundler.require` loads it by the gem name too.

## Configuring your API key

Load the key from the environment or a secret manager. Never commit it, and never inline it in source.

```bash
# .env — excluded from version control
PACTMAN_API_KEY=your_api_key_here
```

```ruby
client = Pactman::NonprofitCheckPlus::Client.new(api_key: ENV.fetch("PACTMAN_API_KEY"))
```

The key is validated locally. A missing, empty, or whitespace-only key raises `ConfigurationError` at construction, before any network call:

```ruby
Pactman::NonprofitCheckPlus::Client.new(api_key: "")
# => Pactman::NonprofitCheckPlus::ConfigurationError: The Pactman API key is empty. Check that
#    the environment variable holding it is set.
```

Every request carries the key as `Authorization: Bearer <key>`. It never appears in error messages, `client.inspect`, `pp client`, `client.to_json` or `client.to_yaml`.

## Quick start

```ruby
require "pactman/nonprofit_check_plus"

client = Pactman::NonprofitCheckPlus::Client.new(api_key: ENV.fetch("PACTMAN_API_KEY"))

result = client.nonprofits.check("41-1787097")

result.nonprofit&.organization_name # => "EXAMPLE NONPROFIT"
result.nonprofit&.pub78_verified    # => true
result.check_count                  # => checks used so far this billing cycle
```

The snippets below write `NCP` for the namespace. Alias it the same way if you like:

```ruby
NCP = Pactman::NonprofitCheckPlus
```

## Environment and base URL

Production is the default and the only named environment. Pactman's QA and sandbox hosts are internal and are not selectable from this gem.

```ruby
# These are equivalent.
NCP::Client.new(api_key: api_key)
NCP::Client.new(api_key: api_key, environment: NCP::Environment::PRODUCTION)
```

For a local mock server, a proxy, or a host Pactman has given you directly, set `base_url:`. It overrides `environment:`, and is validated locally — a malformed URL raises `ConfigurationError` before a request is attempted. `base_url: nil` means "not given", so `ENV.fetch("PACTMAN_BASE_URL", nil)` can be passed straight through.

```ruby
client = NCP::Client.new(api_key: api_key, base_url: "http://127.0.0.1:4010")

client.base_url    # => "http://127.0.0.1:4010"
client.environment # => nil — an explicit host, not a named environment
```

Only the target host changes. Request and response semantics are identical.

## Single check

```ruby
result = client.nonprofits.check("41-1787097")

result.nonprofit     # => Pactman::NonprofitCheckPlus::Nonprofit, or nil
result.check_count   # => checks used this billing cycle (see below)
result.time_taken_ms # => server-side processing time
result.request_id    # => correlation id from the response headers, when sent
result.status        # => 200
result.errors        # => item-level errors, normally []
result.raw           # => the complete parsed response body
```

`"41-1787097"` and `"411787097"` are the same request — the EIN is normalized before the URL is built.

## Bulk check

```ruby
result = client.nonprofits.check_bulk(%w[41-1787097 996589560 999999999])

result.organizations.each { |org| puts "#{org.ein} #{org.organization_name}" }

# EINs with no record are not an error — they come back on a 200 response.
result.not_found_eins # => ["999999999"]
result.check_count
```

Behaviour worth knowing:

|                    |                                                                                                                                |
| ------------------ | ------------------------------------------------------------------------------------------------------------------------------ |
| **Batch limit**    | 50 EINs per request, enforced locally before sending. Exposed as `NCP::MAX_BULK_EINS`.                                          |
| **Chunking**       | None. Larger inputs raise rather than silently splitting into several billable requests.                                       |
| **Request order**  | Your EINs are sent exactly as supplied. The SDK never reorders them.                                                           |
| **Response order** | Not guaranteed to match. The API matches by set membership — index `organizations` by `ein`, never pair them positionally.     |
| **Duplicates**     | Sent as supplied, because each one is billable. A repeated EIN still returns one record. Pass `dedupe: true` to collapse.        |
| **Input type**     | An `Array`. Anything else — a `String`, `nil`, a `Set` — raises `ValidationError` locally; call `.to_a` first.                  |
| **Empty input**    | Raises `ValidationError` locally.                                                                                              |
| **One bad EIN**    | The whole batch is rejected locally, identifying the failing index. Nothing is sent.                                           |
| **No matches**     | A batch where nothing matched is an error; a batch where some matched is a 200 with the rest in `not_found_eins`.              |

```ruby
# Opt in to deduplication.
client.nonprofits.check_bulk(eins, dedupe: true)

# Index by EIN — the pairing that always holds.
by_ein = result.organizations.to_h { |org| [org.ein, org] }
```

## Usage and billing cycle

`nonprofit_check_count`, surfaced as `result.check_count`, is the number of checks your account has consumed **so far in the current billing cycle**, including the request that returned it. It resets when a new cycle starts.

It is not the size of the request you just made. A bulk call for five EINs does not return `5`.

```ruby
before = client.nonprofits.check(ein)
after = client.nonprofits.check_bulk(eins)

after.check_count                      # => cycle total, e.g. 1_284
after.check_count - before.check_count # => what these requests actually consumed
```

EINs with no matching record are not billed, so a delta can be smaller than the batch you sent. Read the number the API reports rather than reconstructing usage from your input.

## Inspecting source-specific findings

The API returns source fields flat on the organization (`pub78_*`, `bmf_*`, `ofac_*`, and the revocation fields). Read them directly, or use the grouped views in `NCP::Sources` — which copy fields 1:1 and derive nothing.

```ruby
nonprofit = client.nonprofits.check("41-1787097").nonprofit

# IRS Publication 78
pub78 = NCP::Sources.pub78(nonprofit)

if pub78.nil?
  puts "Publication 78 data was not returned for this organization."
else
  pub78.verified    # => true, false or nil
  pub78.most_recent # => date of the Pub 78 record
end

# IRS Business Master File
bmf = NCP::Sources.bmf(nonprofit)
bmf&.status
bmf&.subsection_description

# IRS Automatic Revocation of Exemption
aroe = NCP::Sources.aroe(nonprofit)
aroe&.revocation_code
aroe&.revocation_date
aroe&.reinstatement_date

# OFAC Specially Designated Nationals
NCP::Sources.ofac(nonprofit)&.status # => a sentence describing the finding
```

Each view returns `nil` only when the API returned **no data at all** for that source. That keeps _"the source was not returned"_ distinct from an explicit negative such as `pub78_verified: false`.

**On OFAC:** the API returns `ofac_status` as prose, not a boolean. This SDK deliberately does not expose an `ofac_match?` predicate, because deriving one would mean pattern-matching English that could be reworded at any time. Read the status, or route it to a reviewer.

## Response models and raw data

Field names mirror the wire format exactly, so the API reference and your code use the same names — there is no rename table to keep in sync. Every documented field has a reader; every field, documented or not, is reachable with `[]`.

```ruby
result = client.nonprofits.check("411787097")
nonprofit = result.nonprofit

nonprofit.organization_name        # a documented field
nonprofit["some_future_field"]     # anything the API sent, without an SDK upgrade
nonprofit.key?("organization_name_aka") # returned at all, null included?
nonprofit.keys                     # every field the API returned
result.raw                         # the complete, unmodified envelope
```

A model reads the parsed JSON in place rather than copying it: `nonprofit.to_h` is the very Hash inside `result.raw["data"]`. Readers never coerce, so `nil` and `false` stay distinct wherever the API distinguishes them, and a field the API returned as `null` (`key?` is true, value `nil`) stays distinguishable from one it did not return (`key?` is false).

## EIN validation and normalization

```ruby
NCP::EIN.normalize("41-1787097") # => "411787097"
NCP::EIN.normalize("411787097")  # => "411787097"
NCP::EIN.valid?("4117870")       # => false
```

Accepted: nine digits, with or without the conventional hyphen after the two-digit prefix, ignoring surrounding whitespace. Rejected: letters, other punctuation, wrong digit counts, empty strings, `nil`, and anything that is not a `String`. No IRS prefix rules are applied.

Bulk validation reports every failure at once, by index:

```ruby
begin
  client.nonprofits.check_bulk(%w[411787097 nope 1234])
rescue NCP::ValidationError => e
  e.issues.each { |issue| warn "#{issue.index} #{issue.value.inspect} #{issue.message}" }
end
```

> Formatting validation confirms only that a value is shaped like an EIN. It says nothing about tax-exempt status, identity, eligibility, or good standing.

## Error handling

Every error the SDK raises is an `NCP::Error` (a `StandardError`) with a stable `category` and an `origin` of `:local` or `:api`. Rescue by class, or branch on the category — never on message text.

```ruby
begin
  client.nonprofits.check(ein)
rescue NCP::ValidationError
  # Bad input. Nothing was sent.
rescue NCP::AuthenticationError
  # The key was rejected.
rescue NCP::RateLimitError => e
  e.retry_after_seconds
rescue NCP::TimeoutError => e
  e.timeout
rescue NCP::ApiError => e
  [e.status, e.request_id, e.api_errors]
end
```

| Class                 | Category          | Origin   | Raised for                      |
| --------------------- | ----------------- | -------- | ------------------------------- |
| `ConfigurationError`  | `:configuration`  | `:local` | Unusable client options         |
| `ValidationError`     | `:validation`     | `:local` | Input rejected before sending   |
| `BadRequestError`     | `:bad_request`    | `:api`   | HTTP 400                        |
| `AuthenticationError` | `:authentication` | `:api`   | HTTP 401                        |
| `AuthorizationError`  | `:authorization`  | `:api`   | HTTP 403                        |
| `NotFoundError`       | `:not_found`      | `:api`   | HTTP 404                        |
| `RateLimitError`      | `:rate_limit`     | `:api`   | HTTP 429                        |
| `ServerError`         | `:server`         | `:api`   | HTTP 5xx                        |
| `ApiError`            | `:api`            | `:api`   | Any other unexpected response   |
| `TimeoutError`        | `:timeout`        | `:local` | Exceeded the configured timeout |
| `NetworkError`        | `:network`        | `:local` | No response was produced        |

All the HTTP errors inherit from `ApiError`, and carry `status`, `api_code`, `api_message`, `api_errors`, `request_id`, `retry_after_seconds`, `attempts` and `raw`. When a body cannot be parsed, the metadata is still preserved and `raw` holds what the server actually sent. `TimeoutError` and `NetworkError` keep the underlying exception as `cause`.

`error.to_h` and `error.to_json` are sanitized views, safe to log or attach to a support ticket.

An option the client or a method does not have — `timeout_ms:` carried over from the Node.js SDK, say — raises Ruby's own `ArgumentError`, like any other unknown keyword.

## Timeouts and cancellation

The default timeout is **30 seconds** per attempt, exposed as `NCP::DEFAULT_TIMEOUT`. It is always finite — there is no way to disable it — and it is a deadline for the whole attempt, connect to last byte, not a per-read limit.

```ruby
client = NCP::Client.new(api_key: api_key, timeout: 10)

# Or per request.
client.nonprofits.check(ein, timeout: 5)
```

Cancellation is Ruby's own. Kill the thread doing the work, bound the call with `Timeout.timeout`, or stop the task under a fiber scheduler. The SDK never converts a cancellation into one of its errors and never retries through one: the in-flight attempt is abandoned, its socket is closed, and no planned retry runs.

```ruby
worker = Thread.new { client.nonprofits.check(ein) }
worker.kill # nothing keeps running

Timeout.timeout(2) { client.nonprofits.check(ein) } # raises Timeout::Error, not an SDK error
```

A cancellation that arrives as `Thread#raise` should use an exception outside `StandardError`; one inside it is indistinguishable from a transport failure.

## Retries

Enabled by default: up to **2 retries** (3 attempts total), exponential backoff from 0.5 seconds with full jitter, capped at 8 seconds per delay.

```ruby
client = NCP::Client.new(
  api_key: api_key,
  retry: {
    max_retries: 3,
    initial_delay: 0.5,
    max_delay: 8,
    backoff_factor: 2,
    jitter: true,
    retryable_statuses: [429, 500, 502, 503, 504],
    respect_retry_after: true
  }
)

# Disable entirely.
NCP::Client.new(api_key: api_key, retry: false)

# Or override per request. A Hash merges onto the client's policy.
client.nonprofits.check(ein, retry: { max_retries: 0 })
```

Retried: 429, 500, 502, 503, 504, and transport failures that produced no response. **Never** retried: 400, 401, 403, 404, and local validation errors — regardless of `retryable_statuses`. A valid `Retry-After` always takes precedence over computed backoff.

## Rate limits

The API returns HTTP 429 when you exceed your limit. The SDK maps that to `RateLimitError` and exposes `retry_after_seconds`.

```ruby
begin
  client.nonprofits.check(ein)
rescue NCP::RateLimitError => e
  puts "Retry in #{e.retry_after_seconds || 'an unknown number of'} seconds"
end
```

With retries enabled, a 429 is retried automatically after the server's `Retry-After`, falling back to backoff when none is sent.

An optional client-side ceiling is available and off by default:

```ruby
client = NCP::Client.new(api_key: api_key, max_requests_per_second: 3)
```

Server-provided limits are authoritative and may vary by account and endpoint; treat this as a courtesy throttle, not a guarantee. For bulk workloads, prefer the bulk endpoint over concurrent single checks, and keep your own concurrency bounded — the SDK does not queue on your behalf.

## Threads and connections

A client is safe to share across threads, and should be: the request-rate ceiling is per client, so it only bounds what goes through the same one. Build one per process.

The default adapter opens a connection per attempt rather than holding a pool. That keeps the client free of connection state to share between threads, at the cost of a TLS handshake per request — another reason to prefer one bulk call to many single ones. If you need pooled connections, supply an adapter.

## Custom HTTP adapters

`http_adapter:` accepts any object with `#call(request)`, for a connection pool, a proxy library, or a test double.

```ruby
class InstrumentedAdapter
  def initialize(inner = NCP::Http::NetHttpAdapter.new)
    @inner = inner
  end

  def call(request)
    # request.http_method, request.url, request.headers, request.body, request.timeout
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    @inner.call(request)
  ensure
    Metrics.timing("pactman.request", Process.clock_gettime(Process::CLOCK_MONOTONIC) - started)
  end
end

client = NCP::Client.new(api_key: api_key, http_adapter: InstrumentedAdapter.new)
```

The adapter returns an object with `#status`, `#headers` and `#body` (`NCP::Http::Response` will do). To report failure it raises a `Timeout::Error` when `request.timeout` expired, and any other `StandardError` when no response arrived. `request.headers` includes the `Authorization` header, because the adapter has to send it; `request.inspect` does not show it.

## Security

- Load the key from an environment variable or secret manager. Never commit it.
- **Server-side only.** A key that reaches an end user's device is a key anyone can use.
- The key is kept out of every diagnostic surface: error messages, `error.to_h`, `client.inspect`, `pp client`, `client.to_json` and `client.to_yaml`. It lives in a closure, not an instance variable, so nothing that walks the client's state can reach it.
- Rotate the key if it is ever printed, logged, or committed.
- Nonprofit records may be subject to your own retention and privacy obligations. Storing responses is your call, not the SDK's.

## What this SDK does not tell you

The SDK exposes what the API returns and nothing more. It deliberately provides **no** composite `approved`, `eligible`, or `safe` verdict, and no predicate summarizing a source that the API does not itself express as a boolean.

A successful check is data, not a decision. Whether an organization qualifies for a grant, a donation, a match, or a partnership is a determination for your own legal, compliance, grantmaking, and risk policy.

## API reference

**Client** — `Pactman::NonprofitCheckPlus::Client.new(**options)`

| Option                     | Type                           | Default          |                                                  |
| -------------------------- | ------------------------------ | ---------------- | ------------------------------------------------ |
| `api_key:`                 | `String`                       | —                | **Required.**                                    |
| `environment:`             | `Symbol`, `String`             | `:production`    | Named environment.                               |
| `base_url:`                | `String`, `nil`                | —                | Explicit host; overrides `environment:`.         |
| `timeout:`                 | `Numeric`                      | `30`             | Per-attempt deadline, in seconds.                |
| `retry:`                   | `Hash`, `RetryPolicy`, `false` | 2 retries        | Retry policy.                                    |
| `max_requests_per_second:` | `Numeric`, `nil`               | off              | Optional client-side throttle.                   |
| `default_headers:`         | `Hash{String => String}`       | `{}`             | Extra headers; cannot override `Authorization`.  |
| `http_adapter:`            | `#call`                        | `NetHttpAdapter` | Custom HTTP implementation.                      |

Readers: `client.nonprofits`, `client.base_url`, `client.environment`, `client.timeout`, `client.retry_policy`.

**Methods**

- `client.nonprofits.check(ein, timeout:, retry:, headers:)` → `SingleCheckResult`
- `client.nonprofits.check_bulk(eins, dedupe:, timeout:, retry:, headers:)` → `BulkCheckResult`

Every keyword is optional.

**Helpers** — `EIN.normalize`, `EIN.normalize_all`, `EIN.valid?`, `Sources.pub78`, `Sources.bmf`, `Sources.aroe`, `Sources.ofac`, `NCP.supported_environments`, `NCP.base_url_for_environment`

**Constants** — `MAX_BULK_EINS`, `DEFAULT_TIMEOUT`, `DEFAULT_ENVIRONMENT`, `EIN::LENGTH`, `SINGLE_CHECK_PATH`, `BULK_CHECK_PATH`, `VERSION`, `ErrorCategory`, `ErrorOrigin`, `Environment`

**Models** — `Nonprofit`, `OrganizationType`, `ApiErrorDetail`, `SingleCheckResult`, `BulkCheckResult`, `Pub78Source`, `BmfSource`, `AroeSource`, `OfacSource`, `RetryPolicy`, `ValidationIssue`

Public classes and methods carry YARD documentation.

## Examples

Thirty numbered, runnable examples cover secure setup, every source on the response, each error and edge case, bulk semantics, and five end-to-end workflows.

Each one is reproduced below, condensed to the point it makes. Every snippet assumes a `client` from [Quick start](#quick-start) and the `NCP` alias, and omits the output formatting the runnable file uses. The full sources live in [`examples/`](https://github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks/tree/master/ruby/examples) in the repository — they read `PACTMAN_API_KEY` from the environment and contain no credentials.

```bash
git clone https://github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks.git
cd new-pactman-nonprofitcheck-api-sdks/ruby && bundle install

PACTMAN_API_KEY=your_key bundle exec ruby examples/ex_01_secure_client_init.rb
PACTMAN_API_KEY=your_key bundle exec ruby examples/ex_03_identity_lookup.rb 41-1787097
```

Examples for scenarios a live API will not produce on request — a revoked exemption, an OFAC match, an HTTP 429, a response carrying a field newer than this SDK — run against a bundled fixture server they start themselves. CI runs all of them on every push:

```bash
bundle exec rake examples:smoke                       # pass/fail
EXAMPLES_VERBOSE=1 bundle exec rake examples:smoke    # with output
EXAMPLES="ex_22 ex_23" bundle exec rake examples:smoke # a subset
```

Three shorter files sit alongside the numbered set for a first read: [`quickstart.rb`](https://github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks/blob/master/ruby/examples/quickstart.rb), [`bulk.rb`](https://github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks/blob/master/ruby/examples/bulk.rb) and [`error_handling.rb`](https://github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks/blob/master/ruby/examples/error_handling.rb).

### Getting started

#### EX-01 — Secure client initialization

Load the key from the environment, pick an environment, set a finite timeout, build one reusable client — and prove the key reaches no log, no exception, no debug output. [Full source](https://github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks/blob/master/ruby/examples/ex_01_secure_client_init.rb)

```ruby
api_key = ENV.fetch("PACTMAN_API_KEY") # from your secret manager or an ignored .env

# One client, built once, shared for the life of the process.
client = NCP::Client.new(
  api_key: api_key,
  environment: NCP::Environment::PRODUCTION, # the default; naming it is explicit at review time
  timeout: 10                                # the 30s default is often too long for a caller-facing service
)

# Every diagnostic surface, checked against the real key. None of them hold it.
surfaces = [client.inspect, client.to_json, client.to_s, client.to_yaml]

surfaces.any? { |text| text.include?(api_key) } # => false
```

#### EX-02 — EIN normalization

A hyphenated, whitespace-padded EIN normalized to nine digits before the request, with the original kept for diagnostics. [Full source](https://github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks/blob/master/ruby/examples/ex_02_ein_normalization.rb)

```ruby
submitted = "  41-1787097  " # what an onboarding form actually sends

NCP::EIN.valid?(submitted)    # => true
NCP::EIN.normalize(submitted) # => "411787097"

# Store the normalized form as your key — it is what the API echoes back — and
# keep the raw input beside it so support can see what the applicant typed.
applicant = { ein_as_submitted: submitted, ein: NCP::EIN.normalize(submitted) }

# check normalizes internally too, so either form is the same request.
client.nonprofits.check(applicant[:ein_as_submitted]).nonprofit&.ein # => "411787097"
```

#### EX-03 — Identity lookup

EIN, name, AKA and Pactman profile URL, plus the raw envelope alongside the model. [Full source](https://github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks/blob/master/ruby/examples/ex_03_identity_lookup.rb)

```ruby
result = client.nonprofits.check("41-1787097")

if (nonprofit = result.nonprofit)
  nonprofit.ein
  nonprofit.organization_name
  nonprofit.organization_name_aka # frequently nil: "none on file", not "none exists"
  nonprofit.pactman_org_url

  # Response metadata.
  result.status
  result.request_id
  result.time_taken_ms
  result.check_count

  # The model is a view over the envelope, not a replacement for it.
  result.raw["code"]
  result.raw["message"]
  result.raw.dig("data", "ein")
end
```

### Comparing and validating against the record

#### EX-04 — Applicant name comparison

Compare a submitted name with `organization_name` and `organization_name_aka` without treating punctuation or abbreviation differences as fraud. [Full source](https://github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks/blob/master/ruby/examples/ex_04_name_comparison.rb)

```ruby
# The SDK deliberately has no names_match?. What counts as a match is policy,
# so the comparison lives in customer code.
def normalize_name(name)
  name.to_s.upcase.gsub(/\b(INC|INCORPORATED|CORP|CO|LLC|LTD|THE)\b\.?/, "").gsub(/[^A-Z0-9 ]/, " ").squeeze(" ").strip
end

nonprofit = client.nonprofits.check(applicant[:ein]).nonprofit
candidates = [nonprofit&.organization_name, nonprofit&.organization_name_aka].compact

outcome =
  if candidates.empty? then "not_returned" # no name came back — nothing was compared
  elsif candidates.any? { |name| normalize_name(name) == normalize_name(applicant[:legal_name]) } then "agreement"
  else "mismatch"
  end

# A mismatch is a reason to look, not a finding: organizations rebrand, file
# under a parent, and appear in IRS data under a name no donor would recognize.
routed = outcome == "agreement" ? "continue" : "manual_review"
```

#### EX-05 — Validating the returned address

Ask whether the address the API returned is well-formed and self-consistent, before acting on it. [Full source](https://github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks/blob/master/ruby/examples/ex_05_address_validation.rb)

```ruby
nonprofit = client.nonprofits.check(ein).nonprofit

# `state` and `state_name` are two fields for one fact, and the ZIP encodes the
# state a third time. A record can be complete and still contradict itself.
state = nonprofit&.state&.strip&.upcase
zip_digits = (nonprofit&.zip).to_s.gsub(/\D/, "")

missing = %w[address_line1 city state zip].select { |component| (nonprofit&.[](component)).to_s.strip.empty? }

failures = [
  ("state is not a USPS code" unless US_STATES.key?(state)),
  # A check that cannot run reports nothing, never a failure: an incomplete
  # lookup table must not manufacture a finding about somebody's address.
  ("state_name disagrees with state" if nonprofit&.state_name && US_STATES[state] != nonprofit.state_name),
  ("zip is not 5 or 9 digits" unless [5, 9].include?(zip_digits.length)),
  ("zip belongs to another state" if states_for_zip(zip_digits)&.include?(state) == false)
].compact

# Three verdicts, and the middle one is the point. Absence is not validity.
verdict = if failures.any? then "inconsistent"
          elsif missing.any? then "incomplete"
          else "usable"
          end

# Well-formed is not deliverable. USPS, Lob, Smarty and Google Address
# Validation answer that one, over the network, with a second credential.
```

### Reading the sources

#### EX-06 — IRS Business Master File status

Every IRS Business Master File field on the response — status, identity, subsection, exemption, ruling, foundation. [Full source](https://github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks/blob/master/ruby/examples/ex_06_bmf_status.rb)

```ruby
bmf = NCP::Sources.bmf(nonprofit)

if bmf.nil?
  # Not "not in the BMF" — the API returned no BMF fields at all. That is an
  # absence of evidence, not a negative finding. Route it to review.
else
  bmf.status # one source's answer to one question — there is no exempt? here
  bmf.exempt_status_code
  bmf.most_recent

  [bmf.organization_name, bmf.ein, bmf.church_message]
  [bmf.subsection, bmf.subsection_description]
  [bmf.ruling_month, bmf.ruling_year, bmf.group_exemption]
  [bmf.foundation_code, bmf.foundation_code_description]
  [bmf.foundation_type_code, bmf.foundation_type_description, bmf.foundation_509a_status]
  bmf.filing_req_code
end

# Reading the BMF in isolation is how a revoked or sanctioned organization
# passes a check — see EX-08 and EX-10.
```

#### EX-07 — Publication 78 and deductibility

Publication 78 verification and deductibility entries, with a donation policy applied in customer code. [Full source](https://github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks/blob/master/ruby/examples/ex_07_pub78_deductibility.rb)

```ruby
pub78 = NCP::Sources.pub78(nonprofit)

pub78&.verified # => true, false or nil
pub78&.indicator
pub78&.church_message
pub78&.most_recent

# An entry can itself be nil, so read through it rather than into it.
(pub78&.organization_types || []).each do |entry|
  entry&.deductibility_status_description
  entry&.deductibility_limitation
  entry&.organization_type
end

# Your policy, expressed against the source data. Change the predicate, not the
# SDK — nothing here is a verdict the API handed down.
ACCEPTED_LIMITATIONS = %w[50% 60%].freeze

limitations = (pub78&.organization_types || []).filter_map { |entry| entry&.deductibility_limitation }
eligible_under_this_policy = pub78&.verified == true && limitations.intersect?(ACCEPTED_LIMITATIONS)
```

#### EX-08 — Automatic revocation detected

An organization in the IRS Automatic Revocation data, flagged and recorded with its source fields. [Full source](https://github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks/blob/master/ruby/examples/ex_08_automatic_revocation.rb)

```ruby
aroe = NCP::Sources.aroe(nonprofit)
revoked = !(aroe&.revocation_code).to_s.empty? || !(aroe&.revocation_date).to_s.empty?

# The application's policy, in one place, expressed against source fields.
action = if !revoked then "continue"
         elsif aroe.reinstatement_date then "manual_review"
         else "block"
         end

# What you keep is what you can explain later. Store the source fields, the
# request identifier and the time you looked — not just the verdict.
audit_record = {
  ein: nonprofit.ein,
  checked_at: Time.now.utc.iso8601,
  request_id: result.request_id,
  action: action,
  # Revocation shows up in the other sources too.
  source_findings: nonprofit.to_h.slice(
    "revocation_code", "revocation_date", "reinstatement_date", "bmf_status", "pub78_verified"
  )
}
```

#### EX-09 — Revocation with reinstatement

Revocation and reinstatement dates kept separate, and the questions reinstatement does not answer. [Full source](https://github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks/blob/master/ruby/examples/ex_09_revocation_reinstatement.rb)

```ruby
aroe = NCP::Sources.aroe(nonprofit)

# The API formats dates as `M/DD/YYYY h:mm:ss AM`. Parse with that format; do
# not let Time.parse guess, and never reformat in place.
def parse_api_date(value)
  value && Time.strptime(value, "%m/%d/%Y %I:%M:%S %p")
rescue ArgumentError
  nil
end

revoked_at = parse_api_date(aroe&.revocation_date)
reinstated_at = parse_api_date(aroe&.reinstatement_date)

# Nothing collapses the two into a "currently revoked" boolean — that boolean
# would lose the interval, and donations dated inside it may need handling.
lapsed_days = ((reinstated_at - revoked_at) / 86_400).round if revoked_at && reinstated_at

# Reinstatement resolves one question, not every question: was it retroactive?
# Do gifts made during the lapse need re-characterizing? Does your grant
# agreement require continuous exemption? This record still goes to review.
```

#### EX-10 — OFAC screening result

Four distinct OFAC outcomes — no match, match, null, and not screened at all. [Full source](https://github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks/blob/master/ruby/examples/ex_10_ofac_screening.rb)

```ruby
# The SDK exposes no ofac_match? predicate: deriving one means pattern-matching
# English the source can reword at any time. The one textual test below
# escalates and never clears — anything unrecognized falls through to review.
def classify_ofac(nonprofit)
  ofac = NCP::Sources.ofac(nonprofit)

  return "unavailable" if ofac.nil? # no OFAC field at all; nothing was screened
  return "null" if ofac.status.nil?
  return "match" if ofac.status.match?(/UID:/i)
  return "no_match" if ofac.status.match?(/NOT included/i)

  "needs_review"
end

# Four states, four destinations. None of them is "approve automatically".
ROUTING = {
  "no_match" => "continue — screened against the SDN list with no match",
  "match" => "block and escalate to compliance",
  "null" => "hold — the field was returned empty; treat as unscreened, not as cleared",
  "unavailable" => "hold — no OFAC data was returned",
  "needs_review" => "hold — the status text was not recognized by this application"
}.freeze

ROUTING.fetch(classify_ofac(nonprofit))
```

#### EX-11 — Cross-source conflict

`irs_bmf_pub78_conflict` handled by recording both sources, not by picking one. [Full source](https://github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks/blob/master/ruby/examples/ex_11_source_conflict.rb)

```ruby
bmf = NCP::Sources.bmf(nonprofit)
pub78 = NCP::Sources.pub78(nonprofit)
findings = []

# The flag the API sets is authoritative; the comparisons only explain it.
findings << "The API flagged a BMF / Publication 78 disagreement." if nonprofit.irs_bmf_pub78_conflict == true

if bmf&.status == true && pub78&.verified == false
  findings << "The BMF lists the organization as exempt; Publication 78 does not list it."
end

if bmf&.status == false && pub78&.verified == true
  findings << "Publication 78 lists the organization; the BMF does not show it as exempt."
end

# Both sides are kept, side by side, for the reviewer. Silently preferring one
# source means being wrong for some organization with the evidence destroyed.
review_record = { ein: nonprofit.ein, request_id: result.request_id, findings:, sources: { bmf:, pub78: } } if findings.any?
```

#### EX-12 — Organization type and foundation classification

Organization types, foundation and subsection classification for a grantmaker or DAF display. [Full source](https://github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks/blob/master/ruby/examples/ex_12_foundation_classification.rb)

```ruby
bmf = NCP::Sources.bmf(nonprofit)
pub78 = NCP::Sources.pub78(nonprofit)

# What a grant officer sees. Every value is copied, none is computed — and the
# descriptions come from the API's own *_description fields, which stay correct
# when the source changes. A lookup table in your repository does not.
classification_panel = {
  subsection: bmf&.subsection_description,
  foundation_code: bmf&.foundation_code_description,
  foundation_type: bmf&.foundation_type_description,
  status_509a: bmf&.foundation_509a_status,
  entries: pub78&.organization_types
}

# A private foundation grantee is not disqualified — it is routed differently,
# because expenditure responsibility and the deductibility limit both change.
private_foundation = bmf&.foundation_type_code == "pf"
```

#### EX-13 — Filing and exemption metadata

Filing and exemption codes preserved exactly, or mapped through documented tables with an unknown-value fallback. [Full source](https://github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks/blob/master/ruby/examples/ex_13_filing_exemption_metadata.rb)

```ruby
FILING_REQUIREMENTS = { "01" => "990 (all other) or 990-EZ return", "02" => "990 - Required to file Form 990-N" }.freeze

# A documented table with an explicit unknown fallback. A value the IRS adds
# reads as "unrecognized" — never as nil, and never as the wrong label.
def describe(table, code)
  return { code:, known: false, summary: "<not returned>" } if code.nil?

  description = table[code]
  { code:, known: !description.nil?, summary: description || "unrecognized code #{code.inspect}" }
end

bmf = NCP::Sources.bmf(nonprofit)

describe(FILING_REQUIREMENTS, bmf&.filing_req_code)

# Codes the API already describes for you: read its description, do not shadow
# it with a local table that will drift.
[bmf&.subsection, bmf&.subsection_description]
[bmf&.foundation_code, bmf&.foundation_code_description]
[bmf&.ruling_month, bmf&.ruling_year] # raw values, preserved exactly, nil included

# Never coerce an unrecognized code to a default. "Unknown" is a real state,
# and it usually means review rather than approval.
```

#### EX-14 — Data freshness and report metadata

Source timestamps, report date and request timing, feeding an application-owned re-review rule. [Full source](https://github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks/blob/master/ruby/examples/ex_14_data_freshness.rb)

```ruby
# Your rule. The SDK has no stale? and no default threshold, because 90 days is
# prudent for one workflow and reckless for another.
RE_REVIEW_AFTER_DAYS = 90

timestamps = nonprofit.to_h.slice(
  "organization_info_last_modified",
  "report_date",       # when this response was generated
  "most_recent_bmf",   # when each list was last refreshed
  "most_recent_pub78"
)

ages = timestamps.transform_values do |value|
  parsed = parse_api_date(value) # see EX-09
  parsed && ((Time.now - parsed) / 86_400).round
end

undated = ages.select { |_name, age| age.nil? }.keys
oldest = ages.values.compact.max || 0

# The oldest source governs, and an undated source is not a fresh one.
needs_re_review = oldest > RE_REVIEW_AFTER_DAYS || undated.any?

# Store the timestamps with the verification record, not just the outcome. "We
# checked and it was fine" is not an answer six months later; "we checked on
# this date against BMF data published on that date" is.
evidence = { ein: nonprofit.ein, checked_at: Time.now.utc.iso8601, request_id: result.request_id, **timestamps }
```

### Errors and edge cases

#### EX-15 — Malformed EIN rejected locally

Every malformed shape rejected locally, with an instrumented adapter proving no request was sent. [Full source](https://github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks/blob/master/ruby/examples/ex_15_malformed_ein.rb)

```ruby
# A counting wrapper around the default adapter, to prove the claim rather than
# assert it. If any call below reaches the network, this number moves.
requests_sent = 0
inner = NCP::Http::NetHttpAdapter.new
counting = lambda do |request|
  requests_sent += 1
  inner.call(request)
end

client = NCP::Client.new(api_key: ENV.fetch("PACTMAN_API_KEY"), http_adapter: counting)

["41178709", "4117870977", "41-178709A", "", "   ", nil, 411_787_097, "41.1787097", "411-787097"].each do |value|
  client.nonprofits.check(value)
rescue NCP::ValidationError => e
  e.origin       # => :local
  e.issues.first # => index, value, message — enough to highlight the form field
end

# Bulk reports every failure at once, by index.
begin
  client.nonprofits.check_bulk(%w[411787097 nope 996589560])
rescue NCP::ValidationError => e
  e.issues
end

requests_sent # => 0 — bad input costs no quota, no latency, no rate-limit budget
```

#### EX-16 — EIN not found

A well-formed EIN with no record: `NotFoundError`, sanitized diagnostics, and why bulk behaves differently. [Full source](https://github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks/blob/master/ruby/examples/ex_16_not_found.rb)

```ruby
begin
  client.nonprofits.check("999999999")
rescue NCP::NotFoundError => e
  # Stable identity: class, category, origin. Never parse `message`.
  e.category             # => :not_found
  e.origin               # => :api
  e.is_a?(NCP::ApiError) # => true — rescue the specific case or the general one

  # The envelope's own detail survives onto the error.
  [e.status, e.api_code, e.api_message, e.request_id, e.api_errors]
  e.attempts # => 1 — not-found is not a transient failure, so it is never retried

  e.to_json # sanitized: safe to log, safe to attach to a support ticket
end

# The bulk endpoint behaves differently: unmatched EINs come back on a 200.
mixed = client.nonprofits.check_bulk(%w[411787097 999999999])

mixed.status         # => 200
mixed.not_found_eins # => ["999999999"]

# Only a request where nothing at all matched is a 404.
```

#### EX-22 — Rate limits and `Retry-After`

HTTP 429, `Retry-After`, bounded retries, a client-side rate ceiling and a bounded pool of threads. [Full source](https://github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks/blob/master/ruby/examples/ex_22_rate_limit.rb)

```ruby
# 1. Retries off, so the 429 reaches the caller untouched.
begin
  client.nonprofits.check(ein, retry: false)
rescue NCP::RateLimitError => e
  e.status              # => 429
  e.retry_after_seconds # => the server's number, when it sent one
  [e.request_id, e.attempts, e.api_errors]

  # Schedule your own backoff from the server's number; fall back when absent.
  retry_at = Time.now + (e.retry_after_seconds || 5)
end

# 2. Bounded automatic retry. Retry-After wins over computed backoff, and
#    retries stay finite — the SDK never retries indefinitely.
client.nonprofits.check(ein, retry: { max_retries: 1, respect_retry_after: true })

# 3. Reduce pressure rather than absorb rejections: cap the outbound rate, keep
#    your own concurrency small, and prefer one bulk call to a fan-out of
#    single ones. The SDK does not queue on your behalf.
paced = NCP::Client.new(api_key: api_key, max_requests_per_second: 3, retry: { max_retries: 2 })
```

#### EX-23 — Transient failures and retries

Transient 5xx and connection failures retried with jittered backoff; auth, validation and not-found never retried. [Full source](https://github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks/blob/master/ruby/examples/ex_23_transient_retries.rb)

```ruby
# Two 503s absorbed, one successful result returned to the caller. Backoff
# grows exponentially and is jittered, so parallel clients scatter.
result = client.nonprofits.check(ein, retry: { max_retries: 3, initial_delay: 0.5, max_delay: 8 })

# Never retried, whatever retryable_statuses contains. Retrying a 404 cannot
# make a record exist; retrying a rejected key just burns it three times.
begin
  client.nonprofits.check(missing_ein, retry: { max_retries: 5, retryable_statuses: [404, 500] })
rescue NCP::NotFoundError => e
  e.attempts # => 1
end

# A connection that never reached a server: retried, then surfaced with the
# attempt count and the underlying exception. Local validation never reaches
# the network at all.
begin
  unreachable.nonprofits.check(ein)
rescue NCP::NetworkError => e
  [e.attempts, e.cause] # => [3, #<Errno::ECONNREFUSED ...>]
end

# A retried failure that exhausts its budget is an outage. Record it as "not
# checked", never as a pass.
```

#### EX-24 — Timeouts and cancellation

`TimeoutError` and Ruby's own cancellation kept distinguishable, with no work left running. [Full source](https://github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks/blob/master/ruby/examples/ex_24_timeout_and_cancellation.rb)

```ruby
# Two different events, two different types. Conflating them hides which side
# gave up: a timeout means raise the budget or shed load; a cancellation means
# the caller went away.
begin
  client.nonprofits.check(ein, timeout: 0.25, retry: false)
rescue NCP::TimeoutError => e
  e.timeout  # => 0.25 — the deadline you configured expired
  e.category # => :timeout, origin :local
end

# Cancellation is Ruby's own, and the SDK stays out of its way.
worker = Thread.new { client.nonprofits.check(ein, timeout: 10) }
worker.kill  # abandons the in-flight attempt and every retry still planned
worker.join
worker.alive? # => false

begin
  Timeout.timeout(0.2) { client.nonprofits.check(ein, timeout: 10) }
rescue Timeout::Error => e
  e.is_a?(NCP::Error) # => false — the caller's deadline, not the API's failure
end
```

#### EX-25 — Raw response and forward compatibility

An approved fixture from a newer API version: unknown fields and an unknown enum value, both readable, neither fatal. [Full source](https://github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks/blob/master/ruby/examples/ex_25_raw_and_forward_compat.rb)

```ruby
result = client.nonprofits.check(ein)
nonprofit = result.nonprofit

# Known fields read exactly as they always have.
NCP::Sources.bmf(nonprofit)&.status

# Fields this SDK version does not declare ride along on the same object. They
# have no reader, so reach them with [] and check what you got. No upgrade.
registration = nonprofit["state_charity_registration_status"]

if registration.is_a?(String)
  # …
end

# An unrecognized value in a documented field. This is the case that breaks
# applications which map eagerly into an enum and default the miss.
KNOWN_FOUNDATION_TYPES = %w[pc pf po].freeze
foundation_type = NCP::Sources.bmf(nonprofit)&.foundation_type_code

handled = if KNOWN_FOUNDATION_TYPES.include?(foundation_type)
            "a known classification"
          else
            "unknown — routed to review, not defaulted to a known type"
          end

result.raw                                  # the parsed body, unmodified — persist it to prove what the API said
result.raw["data"].equal?(nonprofit.to_h)   # => true
```

### Bulk

#### EX-17 — Bulk screening of a list

Screening a grantee list, iterating organization-level results and reading the response envelope. [Full source](https://github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks/blob/master/ruby/examples/ex_17_bulk_screening.rb)

```ruby
# One bulk request is one round trip and one rate-limit slot. Prefer it to a
# loop of single checks.
result = client.nonprofits.check_bulk(portfolio.map { |entry| entry[:ein] })

[result.status, result.raw["code"], result.time_taken_ms, result.check_count]
[result.organizations.size, result.errors.size, result.not_found_eins]

# Index by EIN. The response is a set of matched records, not a row-for-row
# answer to your input list — see EX-18.
by_ein = result.organizations.to_h { |org| [org.ein, org] }

portfolio.each do |entry|
  org = by_ein[entry[:ein]]
  next if org.nil? # no record returned — not a pass

  puts [org.ein, NCP::Sources.bmf(org)&.status, NCP::Sources.pub78(org)&.verified,
        NCP::Sources.aroe(org)&.revocation_date, NCP::Sources.ofac(org)&.status].inspect
end

result.errors.each { |detail| [detail.resource, detail.code, detail.reason, detail.eins] }
```

#### EX-18 — Input order and duplicate EINs

Response order does not follow request order, duplicates collapse in the response but still bill, and usage is read rather than inferred. [Full source](https://github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks/blob/master/ruby/examples/ex_18_bulk_order_and_duplicates.rb)

```ruby
# Deliberately unsorted, with one EIN repeated. The SDK sends them exactly as
# supplied: it does not reorder and it does not deduplicate.
requested = %w[996589560 411787097 996589560 135562308]

before = client.nonprofits.check("411787097")
result = client.nonprofits.check_bulk(requested)

result.organizations.size # => 3 — the duplicate came back once

# Positional pairing is invalid. This is the pairing that always holds.
by_ein = result.organizations.to_h { |org| [org.ein, org] }

# Usage is reported, not inferred. Every submitted EIN is billable, duplicates
# included, so a count derived from unique inputs will disagree with the invoice.
result.check_count.to_i - before.check_count.to_i

# Opt in when duplicates are an artifact of your data rather than intent.
client.nonprofits.check_bulk(requested, dedupe: true)
```

#### EX-19 — Partial success and item-level errors

Mixed outcomes on one HTTP 200: usable records, item-level errors, and a full input reconciliation. [Full source](https://github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks/blob/master/ruby/examples/ex_19_bulk_partial_success.rb)

```ruby
submitted = %w[411787097 999999999 996589560 123456789]
result = client.nonprofits.check_bulk(submitted)

result.status         # => 200 — some matched and some did not, which is a success
result.organizations  # ordinary records; nothing about a sibling failure degrades them
result.errors         # [ApiErrorDetail] — resource, code, reason, eins
result.not_found_eins

# Reconcile every input against an outcome. This is the loop that keeps a
# portfolio import honest.
matched = result.organizations.to_h { |org| [org.ein, org] }

submitted.each do |ein|
  outcome = if matched.key?(ein) then "matched"
            elsif result.not_found_eins.include?(ein) then "no record — reported in errors"
            else "UNACCOUNTED FOR — do not treat as checked"
            end
end

# An EIN the API has no record for is a gap in the data, not a negative finding
# about the organization. Route it to review; do not record it as "screened".
```

#### EX-20 — Batch-size validation and chunking

Empty and over-limit batches rejected against `MAX_BULK_EINS`, plus chunking a larger list yourself. [Full source](https://github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks/blob/master/ruby/examples/ex_20_bulk_batch_limits.rb)

```ruby
NCP::MAX_BULK_EINS # => 50 — reference it; do not copy the number into your own constants

[[], oversized].each do |batch| # oversized has MAX_BULK_EINS + 1 entries
  client.nonprofits.check_bulk(batch)
rescue NCP::ValidationError => e
  e.origin # => :local — nothing was sent
end

# If the server ever tightens its limit below the SDK's constant, the local
# check passes and the server answers 400. That message is authoritative:
# rescue BadRequestError and log api_errors.map(&:reason) verbatim.

# The SDK never chunks for you, because splitting one batch would quietly turn
# one billable request into several. Do it deliberately.
eins.each_slice(NCP::MAX_BULK_EINS) { |batch| client.nonprofits.check_bulk(batch) }
```

#### EX-21 — Billing-cycle usage tracking

`nonprofit_check_count` as a cumulative billing-cycle total that resets each cycle — never a per-request size. [Full source](https://github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks/blob/master/ruby/examples/ex_21_usage_tracking.rb)

```ruby
first = client.nonprofits.check(ein_a)
bulk = client.nonprofits.check_bulk([ein_a, ein_b, ein_c])

first.check_count                          # => cycle total, e.g. 1_281
bulk.check_count                           # => cycle total again, e.g. 1_284 — not 3
bulk.check_count.to_i - first.check_count.to_i # => what the bulk call consumed

# EINs with no record are not billed, so a delta can be smaller than the batch.
# At the start of a new billing cycle this counter resets to zero.

# Alerting needs your plan's allowance, which the check endpoints do not
# report. Keep it in your own configuration.
allowance = Integer(ENV.fetch("PACTMAN_PLAN_ALLOWANCE", "0"))
utilisation = allowance.positive? ? bulk.check_count.to_f / allowance : nil

# Label this metric "checks used this billing cycle" wherever it is displayed.
# Labelling it "checks in this request" makes a dashboard that resets monthly
# look like a dashboard that is broken.
```

### End-to-end workflows

#### EX-26 — Donation-platform onboarding

Donation-platform onboarding: collect, check, inspect every source, route to approve, reject or review. [Full source](https://github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks/blob/master/ruby/examples/ex_26_onboarding_workflow.rb)

```ruby
# This fictional platform's rules, in one place, reviewable by its compliance
# team. Read them as an illustration of where your policy lives.
POLICY = { stale_after_days: 120, require_pub78_listing: true }.freeze

def onboard(client, applicant)
  begin
    nonprofit = client.nonprofits.check(applicant[:ein]).nonprofit
  rescue NCP::Error
    # A failed lookup is not a rejection. Nothing was learned, so nothing can be
    # concluded — the applicant waits, they are not turned away.
    return { decision: "manual_review", reasons: ["the check could not be completed"] }
  end

  return { decision: "manual_review", reasons: ["no record for this EIN"] } if nonprofit.nil?

  aroe = NCP::Sources.aroe(nonprofit)
  ofac = NCP::Sources.ofac(nonprofit)
  reasons = []

  if aroe&.revocation_date && aroe.reinstatement_date.nil?
    return { decision: "reject", reasons: ["Exemption revoked with no reinstatement."] }
  end

  return { decision: "reject", reasons: ["Possible OFAC SDN match."] } if ofac&.status&.match?(/UID:/i)

  reasons << "IRS sources disagree." if nonprofit.irs_bmf_pub78_conflict == true
  reasons << "Not listed in Publication 78." if POLICY[:require_pub78_listing] && NCP::Sources.pub78(nonprofit)&.verified != true
  reasons << "Submitted name did not match." unless name_agrees?(applicant[:legal_name], nonprofit)

  if reasons.empty?
    { decision: "approve", reasons: ["Every check this platform requires was satisfied."] }
  else
    { decision: "manual_review", reasons: reasons }
  end
end

# The platform decided; the SDK did not.
```

#### EX-27 — DAF grant-recommendation screening

DAF grant-recommendation screening, with a stricter policy than EX-26 over identical data. [Full source](https://github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks/blob/master/ruby/examples/ex_27_daf_grant_screening.rb)

```ruby
# One bulk call for the whole recommendation batch.
result = client.nonprofits.check_bulk(recommendations.map { |entry| entry[:ein] })
by_ein = result.organizations.to_h { |org| [org.ein, org] }

decisions = recommendations.map do |recommendation|
  org = by_ein[recommendation[:ein]]

  # No record was returned. Nothing was verified.
  next recommendation.merge(outcome: "held", queue: "grants_review") if org.nil?

  aroe = NCP::Sources.aroe(org)

  outcome, queue =
    if NCP::Sources.ofac(org)&.status&.match?(/UID:/i) then %w[blocked sanctions_review]
    elsif aroe&.revocation_date && aroe.reinstatement_date.nil? then %w[blocked tax_status_review]
    elsif org.irs_bmf_pub78_conflict == true then %w[held source_conflict_review]
    elsif NCP::Sources.bmf(org)&.foundation_type_code == "pf" then %w[held expenditure_responsibility] # not refused: a different path
    else %w[advanced ready_for_approval]
    end

  recommendation.merge(outcome:, queue:, screened_at: Time.now.utc.iso8601, request_id: result.request_id)
end

# Same API data as EX-26, different obligations, different outcomes. That
# difference is precisely why the SDK does not decide.
```

#### EX-28 — CRM enrichment and synchronization

CRM sync keyed on EIN, where a `null` from the API never erases better customer data. [Full source](https://github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks/blob/master/ruby/examples/ex_28_crm_enrichment.rb)

```ruby
SYNCED_FIELDS = %w[
  organization_name organization_name_aka
  address_line1 address_line2 city state state_name zip
  subsection_description foundation_type_description
  bmf_status pub78_verified pactman_org_url organization_info_last_modified
].freeze

# A field is written only when the API returned a usable value. `null` and
# absent both mean "no update available" — never "clear this". A sync that
# overwrites a good, human-entered address with nil is a data-loss bug that
# looks like a feature until someone notices.
def merge(record, nonprofit)
  SYNCED_FIELDS.each_with_object(record.dup) do |key, row|
    row[key] = nonprofit[key] unless nonprofit[key].nil? # keep what the CRM holds
  end
end

# EIN is the join key: stable, returned on every record, already in your CRM.
# Names change; EINs do not.
result = client.nonprofits.check_bulk(crm.keys)
by_ein = result.organizations.to_h { |org| [org.ein, org] }

crm.each_key do |ein|
  nonprofit = by_ein[ein]

  if nonprofit.nil?
    # A failed lookup is not new information. Leave the row untouched.
    crm[ein] = crm[ein].merge("last_sync_attempt_at" => Time.now.utc.iso8601)
    next
  end

  crm[ein] = merge(crm[ein], nonprofit).merge(
    "verified_at" => Time.now.utc.iso8601,         # without this, a row checked yesterday and
    "verification_request_id" => result.request_id, # one imported in 2019 look identical
    "verification_report_date" => nonprofit.report_date
  )
end
```

#### EX-29 — Pre-disbursement recheck

Recheck immediately before a payout; a material change pauses it and both evidence sets are kept. [Full source](https://github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks/blob/master/ruby/examples/ex_29_pre_disbursement_recheck.rb)

```ruby
# Changes that stop a disbursement outright at this organization.
BLOCKING = %w[revocation_code revocation_date ofac_state bmf_status pub78_verified irs_bmf_pub78_conflict].freeze

def recheck(client, payment, stored)
  begin
    # Retries stay on: a transient failure should be absorbed, not turned into
    # a false "changed" signal.
    result = client.nonprofits.check(payment[:ein], timeout: 10)
  rescue NCP::Error
    # An unreachable API is not evidence that anything is fine.
    return { decision: "hold", reason: "recheck_failed" }
  end

  return { decision: "hold", reason: "no_record" } if result.nonprofit.nil?

  # collect_findings is your own projection of the response — store findings,
  # not a verdict: "approved" alone cannot be re-examined.
  current = collect_findings(result.nonprofit)
  changes = current.keys.reject { |key| current[key] == stored[:findings][key] }
  blocking = changes & BLOCKING

  # Both snapshots are kept. Neither overwrites the other.
  {
    decision: blocking.empty? ? "release" : "hold",
    prior_verification: stored,
    current_verification: { checked_at: Time.now.utc.iso8601, request_id: result.request_id,
                            report_date: result.nonprofit.report_date, findings: current },
    changes: changes
  }
end

# An organization approved at onboarding is not an organization approved today.
# Recheck as close to the money movement as your workflow allows.
```

#### EX-30 — Scheduled portfolio re-verification

Scheduled bulk re-verification with a diff against the last run and an explainable audit trail. [Full source](https://github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks/blob/master/ruby/examples/ex_30_portfolio_reverification.rb)

```ruby
# Identify the rules that produced an outcome, so old entries stay readable.
POLICY_VERSION = "2026.02-portfolio-rev3"
RE_REVIEW_INTERVAL_DAYS = 90

records = {}

portfolio.map { |entry| entry[:ein] }.each_slice(NCP::MAX_BULK_EINS) do |eins|
  result = client.nonprofits.check_bulk(eins)

  result.organizations.each { |org| records[org.ein] = { org:, request_id: result.request_id } }

  # An EIN that produced no record is unverified this cycle, not clean.
  result.not_found_eins.each { |ein| records[ein] = { org: nil, request_id: result.request_id } }
end

portfolio.each do |entry|
  record = records[entry[:ein]]
  findings = record&.dig(:org) && collect_findings(record[:org])

  # A first run has nothing to compare against; say so rather than reporting
  # every field as "changed".
  baseline = entry[:last_findings].nil?
  changes = baseline || findings.nil? ? [] : diff_findings(entry[:last_findings], findings)

  audit_log << {
    ein: entry[:ein],
    checked_at: run_started_at.utc.iso8601,
    request_id: record&.dig(:request_id), # identifiers are stored; API keys never are
    policy_version: POLICY_VERSION,
    outcome: outcome_for(findings, changes), # suspend | review | retain
    changes:,
    findings:,
    next_review_due: (run_started_at + (RE_REVIEW_INTERVAL_DAYS * 86_400)).utc.iso8601
  }

  entry[:last_findings] = findings # carry the snapshot forward for the next run
end

# What makes an audit trail useful is the evidence next to the outcome: when
# the check ran, which request it was, what each source said, and which policy
# version read them.
```

### One thing every example repeats

The SDK reports what the API returned. It produces no `approved`, `eligible` or `safe` verdict, and no predicate summarizing a source the API does not itself express as a boolean. Whether an organization qualifies for a donation, a grant, a match or a payout is a determination for your own legal, compliance and risk policy — which is why the routing logic in these examples lives in the example, never in the library.

## Development

```bash
bundle install
bundle exec rake                  # lint and unit tests
bundle exec rake examples:smoke   # every example against the bundled mock server
bundle exec rake mock             # the mock server on PORT (default 4010)
```

To check a live deployment against this gem's response contract and the committed recording of production — and to see any schema drift — run the live smoke test. It spends real quota, and prints what it will cost before the first request goes out:

```bash
PACTMAN_API_KEY=your_key bundle exec ruby scripts/smoke_live.rb <ein> <bulk-eins> <missing-ein>
```

`bundle exec rake baseline:record` re-records `response_baseline.json` from production, and only needs running when production has moved and the move is intended.

## Support

- API documentation: <https://pactman.org/nonprofitcheckplus-api/docs>
- Pactman: <https://pactman.org>
- Issues: <https://github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks/issues>

## License

MIT — see [LICENSE](./LICENSE).
