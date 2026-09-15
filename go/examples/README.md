# Examples

Runnable examples for the Go SDK. Every one reads `PACTMAN_API_KEY` from the
environment and contains no credentials.

```bash
PACTMAN_API_KEY=your_key go run ./examples/ex-01-secure-client-init
```

Run all of them against the bundled fixture API, which is what CI does:

```bash
go run ./internal/devtools examples-smoke                     # pass/fail only
EXAMPLES_VERBOSE=1 go run ./internal/devtools examples-smoke  # with their output
go run ./internal/devtools examples-smoke ex-22 ex-23         # a subset
```

The smoke run needs no key and no network: one fixture server is started, every
example is pointed at it, and an example that did not get the outcome it
demonstrates exits non-zero and fails the run. It also asserts one thing about
content — that no example prints the credential it was given.

## Where each example runs

| Target                            | Examples                                                        |                                                                                                                                                                                       |
| --------------------------------- | --------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Production, or `PACTMAN_BASE_URL` | `ex-01`, `ex-02`, `ex-15`                                       | Client construction and local validation. `ex-02` and `ex-15` send nothing at all.                                                                                                    |
| The bundled fixture API           | everything else                                                 | Needs a record or a response a live API will not produce on request: a revoked exemption, an OFAC match, an HTTP 429, an address that contradicts itself, a field newer than this SDK. |

Fixture-backed examples start the bundled fixture API themselves and shut it
down on the way out. Set `PACTMAN_BASE_URL` to point them somewhere else — a
mock of your own, or a host Pactman has given you. Fixture records live in
[`internal/mockapi/fixtures.go`](../internal/mockapi/fixtures.go).

## The examples

### Getting started

|       |                                                                            |                                                                                                                                                                             |
| ----- | -------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| EX-01 | [ex-01-secure-client-init](./ex-01-secure-client-init/main.go)             | Load the key from the environment, pick an environment, set a finite timeout, build one reusable client — and prove the key reaches no `fmt` verb, no `slog` line, no error. |
| EX-02 | [ex-02-ein-normalization](./ex-02-ein-normalization/main.go)               | Every accepted spelling of an EIN and every rejected one, with `Issues` naming each bad row by index.                                                                       |
| EX-03 | [ex-03-identity-lookup](./ex-03-identity-lookup/main.go)                   | The identity fields, and `Fields.Has` — the difference between a field returned as null and a field not returned at all.                                                    |

### Comparing and validating against the record

|       |                                                                      |                                                                                                                                                  |
| ----- | -------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------ |
| EX-04 | [ex-04-name-comparison](./ex-04-name-comparison/main.go)             | Compare a submitted name with `organization_name` and `organization_name_aka` without treating punctuation or abbreviation differences as fraud. |
| EX-05 | [ex-05-address-validation](./ex-05-address-validation/main.go)       | Validate the returned address structurally. Complete is not the same as correct.                                                                |

### Reading the sources

|       |                                                                                    |                                                                                                       |
| ----- | ---------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------- |
| EX-06 | [ex-06-bmf-status](./ex-06-bmf-status/main.go)                                     | Every IRS Business Master File field, and why `bmf_status` is a `*bool` with three states.            |
| EX-07 | [ex-07-pub78-deductibility](./ex-07-pub78-deductibility/main.go)                   | Publication 78 verification and deductibility entries, with a donation policy applied in caller code. |
| EX-08 | [ex-08-automatic-revocation](./ex-08-automatic-revocation/main.go)                 | An organization in the IRS Automatic Revocation data, read across every source that reports it.       |
| EX-09 | [ex-09-revocation-reinstatement](./ex-09-revocation-reinstatement/main.go)         | Revocation and reinstatement dates kept separate, and the question reinstatement does not answer.     |
| EX-10 | [ex-10-ofac-screening](./ex-10-ofac-screening/main.go)                             | Four distinct OFAC outcomes — no match, match, null, and not screened at all.                         |
| EX-11 | [ex-11-source-conflict](./ex-11-source-conflict/main.go)                           | `irs_bmf_pub78_conflict` handled by recording both sources, not by picking one.                        |
| EX-12 | [ex-12-foundation-classification](./ex-12-foundation-classification/main.go)       | Foundation and subsection classification for a grantmaker or DAF display.                             |
| EX-13 | [ex-13-filing-exemption-metadata](./ex-13-filing-exemption-metadata/main.go)       | Filing and exemption codes mapped through local tables with an unknown-value fallback.                |
| EX-14 | [ex-14-data-freshness](./ex-14-data-freshness/main.go)                             | Source timestamps and report date, feeding an application-owned re-review rule.                       |

### Errors and edge cases

|       |                                                                                |                                                                                                                                     |
| ----- | ------------------------------------------------------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------- |
| EX-15 | [ex-15-malformed-ein](./ex-15-malformed-ein/main.go)                           | Every malformed shape rejected locally, with a counting `HTTPDoer` proving no request was sent.                                     |
| EX-16 | [ex-16-not-found](./ex-16-not-found/main.go)                                   | A well-formed EIN with no record: `ErrNotFound`, sanitized diagnostics, and why bulk behaves differently.                           |
| EX-22 | [ex-22-rate-limit](./ex-22-rate-limit/main.go)                                 | HTTP 429, `Retry-After`, bounded retries, a client-side ceiling and a bounded worker pool.                                         |
| EX-23 | [ex-23-transient-retries](./ex-23-transient-retries/main.go)                   | Transient 5xx retried with jittered backoff; auth, validation and not-found never retried.                                         |
| EX-24 | [ex-24-timeout-and-cancellation](./ex-24-timeout-and-cancellation/main.go)     | `*TimeoutError`, `context.Canceled` and the caller's own deadline, kept distinguishable — with no work left running.                |
| EX-25 | [ex-25-raw-and-forward-compat](./ex-25-raw-and-forward-compat/main.go)         | Records from a newer API version: unknown fields and an unknown enum value, both readable, neither fatal.                           |

### Bulk

|       |                                                                                    |                                                                                                                                           |
| ----- | ---------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------- |
| EX-17 | [ex-17-bulk-screening](./ex-17-bulk-screening/main.go)                             | Screening a grantee list, iterating organization-level results and reading the response envelope.                                         |
| EX-18 | [ex-18-bulk-order-and-duplicates](./ex-18-bulk-order-and-duplicates/main.go)       | Response order does not follow request order, duplicates collapse in the response but still bill, and `WithDedupe` is the opt-in.         |
| EX-19 | [ex-19-bulk-partial-success](./ex-19-bulk-partial-success/main.go)                 | Mixed outcomes on one HTTP 200 with a nil error: usable records, item-level errors, and a full input reconciliation.                      |
| EX-20 | [ex-20-bulk-batch-limits](./ex-20-bulk-batch-limits/main.go)                       | Empty and over-limit batches rejected against `MaxBulkEINs`, plus chunking a larger list yourself.                                        |
| EX-21 | [ex-21-usage-tracking](./ex-21-usage-tracking/main.go)                             | `CheckCount` as a cumulative billing-cycle total that resets each cycle — never a per-request size.                                       |

### End-to-end workflows

|       |                                                                                  |                                                                                                         |
| ----- | -------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------- |
| EX-26 | [ex-26-onboarding-workflow](./ex-26-onboarding-workflow/main.go)                 | Donation-platform onboarding: collect, check, inspect every source, route to proceed or to a reviewer. |
| EX-27 | [ex-27-daf-grant-screening](./ex-27-daf-grant-screening/main.go)                 | DAF grant screening, with a stricter policy than EX-26 over identical data.                            |
| EX-28 | [ex-28-crm-enrichment](./ex-28-crm-enrichment/main.go)                           | CRM sync keyed on EIN, where a null from the API never erases better customer data.                    |
| EX-29 | [ex-29-pre-disbursement-recheck](./ex-29-pre-disbursement-recheck/main.go)       | A re-check in the path of a payment that fails closed when it cannot complete.                         |
| EX-30 | [ex-30-portfolio-reverification](./ex-30-portfolio-reverification/main.go)       | A scheduled bulk sweep that produces a work queue, reporting changes in both directions.               |

### Originals

|                                                        |                                            |
| ------------------------------------------------------ | ------------------------------------------ |
| [quickstart](./quickstart/main.go)                     | The shortest useful single check.          |
| [bulk](./bulk/main.go)                                 | The shortest useful bulk check.            |
| [error-handling](./error-handling/main.go)             | Branching on error category in one place.  |

## Shared helpers

[`internal/support`](./internal/support) holds the pieces the numbered examples
share, so each file stays on its own subject. None of it is part of the SDK, and
it is under `internal/` so that it cannot be mistaken for public API.

|                                                              |                                                                                                |
| ------------------------------------------------------------ | ---------------------------------------------------------------------------------------------- |
| [context.go](./internal/support/context.go)                  | Reads the key and builds a client — the distilled form of EX-01 — and starts the fixture API.  |
| [output.go](./internal/support/output.go)                    | Console formatting. Prints `<null>` and `<not returned>` differently, on purpose.              |
| [apidate.go](./internal/support/apidate.go)                  | Parses the API's display-formatted timestamps, and reports an unparseable one as unknown.       |
| [matching.go](./internal/support/matching.go)                | Name comparison, used by EX-04 and the workflows.                                              |
| [addresses.go](./internal/support/addresses.go)              | Structural address validation for EX-05 — state codes, placeholders, cross-source disagreement. |
| [irscodes.go](./internal/support/irscodes.go)                | Lookup tables with an unknown-value fallback, for codes the API returns without a description.  |
| [screening.go](./internal/support/screening.go)              | Gathers findings into one comparable list for the workflow examples. Decides nothing.           |

## One thing every example repeats

The SDK reports what the API returned. It produces no `approved`, `eligible` or
`safe` verdict, and no boolean summarizing a source the API does not itself
express as a boolean. Whether an organization qualifies for a donation, a grant,
a match or a payout is a determination for your own legal, compliance and risk
policy — which is why the routing logic in these examples lives in the example,
never in the library.
