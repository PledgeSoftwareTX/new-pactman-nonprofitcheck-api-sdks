# Examples

Runnable examples for `@pactmandev/nonprofit-check-plus`. Every one reads
`PACTMAN_API_KEY` from the environment and contains no credentials.

```bash
npm run build                                   # examples import the package by name
PACTMAN_API_KEY=your_key node examples/ex-01-secure-client-init.mjs
```

Run all of them against the bundled fixture API, which is what CI does:

```bash
npm run examples:smoke                # all examples, pass/fail only
EXAMPLES_VERBOSE=1 npm run examples:smoke        # with their output
npm run examples:smoke -- ex-22 ex-23            # a subset
```

## Where each example runs

| Target                            | Examples                   |                                                                                                                                                    |
| --------------------------------- | -------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------- |
| Production, or `PACTMAN_BASE_URL` | `ex-01` – `ex-07`, `ex-15` | Ordinary lookups. Pass an EIN as the first argument where noted.                                                                                   |
| The bundled fixture API           | everything else            | Needs a record or a response a live API will not produce on request: a revoked exemption, an OFAC match, an HTTP 429, a field newer than this SDK. |

Fixture-backed examples start [`scripts/mock-server.mjs`](../scripts/mock-server.mjs)
themselves and shut it down on the way out. Set `PACTMAN_BASE_URL` to point them
somewhere else. Fixture records live in [`scripts/fixtures.mjs`](../scripts/fixtures.mjs).

## The examples

### Getting started

|       |                                                                |                                                                                                                                                                            |
| ----- | -------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| EX-01 | [ex-01-secure-client-init.mjs](./ex-01-secure-client-init.mjs) | Load the key from the environment, pick an environment, set a finite timeout, build one reusable client — and prove the key reaches no log, no exception, no debug output. |
| EX-02 | [ex-02-ein-normalization.mjs](./ex-02-ein-normalization.mjs)   | A hyphenated, whitespace-padded EIN normalized to nine digits before the request, with the original kept for diagnostics.                                                  |
| EX-03 | [ex-03-identity-lookup.mjs](./ex-03-identity-lookup.mjs)       | EIN, name, AKA and Pactman profile URL, plus the raw envelope alongside the typed model.                                                                                   |

### Comparing an applicant against the record

|       |                                                                |                                                                                                                                                  |
| ----- | -------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------ |
| EX-04 | [ex-04-name-comparison.mjs](./ex-04-name-comparison.mjs)       | Compare a submitted name with `organization_name` and `organization_name_aka` without treating punctuation or abbreviation differences as fraud. |
| EX-05 | [ex-05-address-comparison.mjs](./ex-05-address-comparison.mjs) | Compare each address component, keeping "did not match" separate from "was not returned".                                                        |

### Reading the sources

|       |                                                                              |                                                                                                                     |
| ----- | ---------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------- |
| EX-06 | [ex-06-bmf-status.mjs](./ex-06-bmf-status.mjs)                               | Every IRS Business Master File field on the response — status, identity, subsection, exemption, ruling, foundation. |
| EX-07 | [ex-07-pub78-deductibility.mjs](./ex-07-pub78-deductibility.mjs)             | Publication 78 verification and deductibility entries, with a donation policy applied in customer code.             |
| EX-08 | [ex-08-automatic-revocation.mjs](./ex-08-automatic-revocation.mjs)           | An organization in the IRS Automatic Revocation data, flagged and recorded with its source fields.                  |
| EX-09 | [ex-09-revocation-reinstatement.mjs](./ex-09-revocation-reinstatement.mjs)   | Revocation and reinstatement dates kept separate, and the questions reinstatement does not answer.                  |
| EX-10 | [ex-10-ofac-screening.mjs](./ex-10-ofac-screening.mjs)                       | Four distinct OFAC outcomes — no match, match, null, and not screened at all.                                       |
| EX-11 | [ex-11-source-conflict.mjs](./ex-11-source-conflict.mjs)                     | `irs_bmf_pub78_conflict` handled by recording both sources, not by picking one.                                     |
| EX-12 | [ex-12-foundation-classification.mjs](./ex-12-foundation-classification.mjs) | Organization types, foundation and subsection classification for a grantmaker or DAF display.                       |
| EX-13 | [ex-13-filing-exemption-metadata.mjs](./ex-13-filing-exemption-metadata.mjs) | Filing and exemption codes preserved exactly, or mapped through documented tables with an unknown-value fallback.   |
| EX-14 | [ex-14-data-freshness.mjs](./ex-14-data-freshness.mjs)                       | Source timestamps, report date and request timing, feeding an application-owned re-review rule.                     |

### Errors and edge cases

|       |                                                                            |                                                                                                                       |
| ----- | -------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------- |
| EX-15 | [ex-15-malformed-ein.mjs](./ex-15-malformed-ein.mjs)                       | Every malformed shape rejected locally, with an instrumented `fetch` proving no request was sent.                     |
| EX-16 | [ex-16-not-found.mjs](./ex-16-not-found.mjs)                               | A well-formed EIN with no record: `PactmanNotFoundError`, sanitized diagnostics, and why bulk behaves differently.    |
| EX-22 | [ex-22-rate-limit.mjs](./ex-22-rate-limit.mjs)                             | HTTP 429, `Retry-After`, bounded retries, a client-side rate ceiling and a bounded concurrency pool.                  |
| EX-23 | [ex-23-transient-retries.mjs](./ex-23-transient-retries.mjs)               | Transient 5xx and connection failures retried with jittered backoff; auth, validation and not-found never retried.    |
| EX-24 | [ex-24-timeout-and-cancellation.mjs](./ex-24-timeout-and-cancellation.mjs) | `PactmanTimeoutError` and `AbortSignal` cancellation kept distinguishable, with no work left running.                 |
| EX-25 | [ex-25-raw-and-forward-compat.mjs](./ex-25-raw-and-forward-compat.mjs)     | An approved fixture from a newer API version: unknown fields and an unknown enum value, both readable, neither fatal. |

### Bulk

|       |                                                                              |                                                                                                                                           |
| ----- | ---------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------- |
| EX-17 | [ex-17-bulk-screening.mjs](./ex-17-bulk-screening.mjs)                       | Screening a grantee list, iterating organization-level results and reading the response envelope.                                         |
| EX-18 | [ex-18-bulk-order-and-duplicates.mjs](./ex-18-bulk-order-and-duplicates.mjs) | Response order does not follow request order, duplicates collapse in the response but still bill, and usage is read rather than inferred. |
| EX-19 | [ex-19-bulk-partial-success.mjs](./ex-19-bulk-partial-success.mjs)           | Mixed outcomes on one HTTP 200: usable records, item-level errors, and a full input reconciliation.                                       |
| EX-20 | [ex-20-bulk-batch-limits.mjs](./ex-20-bulk-batch-limits.mjs)                 | Empty and over-limit batches rejected against `MAX_BULK_EINS`, plus chunking a larger list yourself.                                      |
| EX-21 | [ex-21-usage-tracking.mjs](./ex-21-usage-tracking.mjs)                       | `nonprofit_check_count` as a cumulative billing-cycle total that resets each cycle — never a per-request size.                            |

### End-to-end workflows

|       |                                                                            |                                                                                                         |
| ----- | -------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------- |
| EX-26 | [ex-26-onboarding-workflow.mjs](./ex-26-onboarding-workflow.mjs)           | Donation-platform onboarding: collect, check, inspect every source, route to approve, reject or review. |
| EX-27 | [ex-27-daf-grant-screening.mjs](./ex-27-daf-grant-screening.mjs)           | DAF grant-recommendation screening, with a stricter policy than EX-26 over identical data.              |
| EX-28 | [ex-28-crm-enrichment.mjs](./ex-28-crm-enrichment.mjs)                     | CRM sync keyed on EIN, where a `null` from the API never erases better customer data.                   |
| EX-29 | [ex-29-pre-disbursement-recheck.mjs](./ex-29-pre-disbursement-recheck.mjs) | Recheck immediately before a payout; a material change pauses it and both evidence sets are kept.       |
| EX-30 | [ex-30-portfolio-reverification.mjs](./ex-30-portfolio-reverification.mjs) | Scheduled bulk re-verification with a diff against the last run and an explainable audit trail.         |

### Originals

|                                            |                                       |
| ------------------------------------------ | ------------------------------------- |
| [quickstart.mjs](./quickstart.mjs)         | The shortest useful single check.     |
| [bulk.mjs](./bulk.mjs)                     | The shortest useful bulk check.       |
| [error-handling.mjs](./error-handling.mjs) | Branching on error type in one place. |

## Checking a live deployment

The examples above prove the SDK works. To prove a _deployment_ still matches the
documented contract — and to see any schema drift — run the live smoke test
instead. It spends real quota, so it prints its plan and asks first.

```bash
PACTMAN_API_KEY=your_key npm run smoke:live -- --base-url https://entities.pactman.org --dry-run
```

See [Verifying against a live deployment](../README.md#verifying-against-a-live-deployment).

## Shared helpers

[`lib/`](./lib) holds the small pieces the numbered examples share, so each file
stays on its own subject. None of it is part of the SDK.

|                                              |                                                                                                |
| -------------------------------------------- | ---------------------------------------------------------------------------------------------- |
| [lib/client.mjs](./lib/client.mjs)           | Reads the key and builds a client — the distilled form of EX-01.                               |
| [lib/print.mjs](./lib/print.mjs)             | Console formatting. Prints `<null>` and `<not returned>` differently, on purpose.              |
| [lib/fixture-api.mjs](./lib/fixture-api.mjs) | Starts and stops the fixture API for scenario-based examples.                                  |
| [lib/matching.mjs](./lib/matching.mjs)       | Name and address comparison, used by EX-04, EX-05 and the workflows.                           |
| [lib/irs-codes.mjs](./lib/irs-codes.mjs)     | Lookup tables with an unknown-value fallback, for codes the API returns without a description. |
| [lib/screening.mjs](./lib/screening.mjs)     | Gathers findings into one comparable object for the workflow examples. Decides nothing.        |

## One thing every example repeats

The SDK reports what the API returned. It produces no `approved`, `eligible` or
`safe` verdict, and no boolean summarizing a source the API does not itself
express as a boolean. Whether an organization qualifies for a donation, a grant,
a match or a payout is a determination for your own legal, compliance and risk
policy — which is why the routing logic in these examples lives in the example,
never in the library.
