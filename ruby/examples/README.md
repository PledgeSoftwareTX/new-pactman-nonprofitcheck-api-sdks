# Examples

Runnable examples for `pactman-nonprofit-check-plus`. Every one reads
`PACTMAN_API_KEY` from the environment and contains no credentials.

```bash
bundle install
PACTMAN_API_KEY=your_key bundle exec ruby examples/ex_01_secure_client_init.rb
```

Run all of them against the bundled fixture API, which is what CI does:

```bash
bundle exec rake examples:smoke                        # all examples, pass/fail only
EXAMPLES_VERBOSE=1 bundle exec rake examples:smoke     # with their output
EXAMPLES="ex_22 ex_23" bundle exec rake examples:smoke # a subset
```

## Where each example runs

| Target                            | Examples                                     |                                                                                                                                                                                        |
| --------------------------------- | -------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Production, or `PACTMAN_BASE_URL` | `ex_01` – `ex_04`, `ex_06`, `ex_07`, `ex_15`, `ex_21` | Ordinary lookups. Pass an EIN as the first argument where noted.                                                                                                                       |
| The bundled fixture API           | everything else                              | Needs a record or a response a live API will not produce on request: a revoked exemption, an OFAC match, an HTTP 429, an address that contradicts itself, a field newer than this SDK. |

Fixture-backed examples start [`scripts/mock_server.rb`](../scripts/mock_server.rb)
themselves and shut it down on the way out. Set `PACTMAN_BASE_URL` to point them
somewhere else. Fixture records live in [`scripts/fixtures.rb`](../scripts/fixtures.rb).

## The examples

### Getting started

|       |                                                              |                                                                                                                                                                                     |
| ----- | ------------------------------------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| EX-01 | [ex_01_secure_client_init.rb](./ex_01_secure_client_init.rb) | Load the key from the environment, pick an environment, set a finite timeout, build one reusable client — and prove the key reaches no log, no serializer, no exception, no `pp`. |
| EX-02 | [ex_02_ein_normalization.rb](./ex_02_ein_normalization.rb)   | A hyphenated, whitespace-padded EIN normalized to nine digits before the request, with the original kept for diagnostics.                                                           |
| EX-03 | [ex_03_identity_lookup.rb](./ex_03_identity_lookup.rb)       | EIN, name, AKA and Pactman profile URL, plus the raw envelope alongside the model.                                                                                                  |

### Comparing and validating against the record

|       |                                                              |                                                                                                                                                  |
| ----- | ------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------ |
| EX-04 | [ex_04_name_comparison.rb](./ex_04_name_comparison.rb)       | Compare a submitted name with `organization_name` and `organization_name_aka` without treating punctuation or abbreviation differences as fraud. |
| EX-05 | [ex_05_address_validation.rb](./ex_05_address_validation.rb) | Validate the returned address structurally — present, self-consistent, or neither. Complete is not the same as correct.                          |

### Reading the sources

|       |                                                                            |                                                                                                                     |
| ----- | -------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------- |
| EX-06 | [ex_06_bmf_status.rb](./ex_06_bmf_status.rb)                               | Every IRS Business Master File field on the response — status, identity, subsection, exemption, ruling, foundation. |
| EX-07 | [ex_07_pub78_deductibility.rb](./ex_07_pub78_deductibility.rb)             | Publication 78 verification and deductibility entries, with a donation policy applied in customer code.             |
| EX-08 | [ex_08_automatic_revocation.rb](./ex_08_automatic_revocation.rb)           | An organization in the IRS Automatic Revocation data, flagged and recorded with its source fields.                  |
| EX-09 | [ex_09_revocation_reinstatement.rb](./ex_09_revocation_reinstatement.rb)   | Revocation and reinstatement dates kept separate, and the questions reinstatement does not answer.                  |
| EX-10 | [ex_10_ofac_screening.rb](./ex_10_ofac_screening.rb)                       | Four distinct OFAC outcomes — no match, match, null, and not screened at all.                                       |
| EX-11 | [ex_11_source_conflict.rb](./ex_11_source_conflict.rb)                     | `irs_bmf_pub78_conflict` handled by recording both sources, not by picking one.                                     |
| EX-12 | [ex_12_foundation_classification.rb](./ex_12_foundation_classification.rb) | Organization types, foundation and subsection classification for a grantmaker or DAF display.                       |
| EX-13 | [ex_13_filing_exemption_metadata.rb](./ex_13_filing_exemption_metadata.rb) | Filing and exemption codes preserved exactly, or mapped through documented tables with an unknown-value fallback.   |
| EX-14 | [ex_14_data_freshness.rb](./ex_14_data_freshness.rb)                       | Source timestamps, report date and request timing, feeding an application-owned re-review rule.                     |

### Errors and edge cases

|       |                                                                          |                                                                                                                               |
| ----- | ------------------------------------------------------------------------ | ----------------------------------------------------------------------------------------------------------------------------- |
| EX-15 | [ex_15_malformed_ein.rb](./ex_15_malformed_ein.rb)                       | Every malformed shape rejected locally, with an instrumented HTTP adapter proving no request was sent.                        |
| EX-16 | [ex_16_not_found.rb](./ex_16_not_found.rb)                               | A well-formed EIN with no record: `NotFoundError`, sanitized diagnostics, and why bulk behaves differently.                   |
| EX-22 | [ex_22_rate_limit.rb](./ex_22_rate_limit.rb)                             | HTTP 429, `Retry-After`, bounded retries, a client-side rate ceiling and a bounded pool of worker threads.                    |
| EX-23 | [ex_23_transient_retries.rb](./ex_23_transient_retries.rb)               | Transient 5xx and connection failures retried with jittered backoff; auth, validation and not-found never retried.            |
| EX-24 | [ex_24_timeout_and_cancellation.rb](./ex_24_timeout_and_cancellation.rb) | `TimeoutError` kept apart from Ruby's own cancellation — `Thread#kill` and `Timeout.timeout` — with no work left running.     |
| EX-25 | [ex_25_raw_and_forward_compat.rb](./ex_25_raw_and_forward_compat.rb)     | An approved fixture from a newer API version: unknown fields and an unknown enum value, both readable, neither fatal.         |

### Bulk

|       |                                                                            |                                                                                                                                           |
| ----- | -------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------- |
| EX-17 | [ex_17_bulk_screening.rb](./ex_17_bulk_screening.rb)                       | Screening a grantee list, iterating organization-level results and reading the response envelope.                                         |
| EX-18 | [ex_18_bulk_order_and_duplicates.rb](./ex_18_bulk_order_and_duplicates.rb) | Response order does not follow request order, duplicates collapse in the response but still bill, and usage is read rather than inferred. |
| EX-19 | [ex_19_bulk_partial_success.rb](./ex_19_bulk_partial_success.rb)           | Mixed outcomes on one HTTP 200: usable records, item-level errors, and a full input reconciliation.                                       |
| EX-20 | [ex_20_bulk_batch_limits.rb](./ex_20_bulk_batch_limits.rb)                 | Empty and over-limit batches rejected against `MAX_BULK_EINS`, plus chunking a larger list yourself.                                      |
| EX-21 | [ex_21_usage_tracking.rb](./ex_21_usage_tracking.rb)                       | `nonprofit_check_count` as a cumulative billing-cycle total that resets each cycle — never a per-request size.                            |

### End-to-end workflows

|       |                                                                          |                                                                                                         |
| ----- | ------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------- |
| EX-26 | [ex_26_onboarding_workflow.rb](./ex_26_onboarding_workflow.rb)           | Donation-platform onboarding: collect, check, inspect every source, route to approve, reject or review. |
| EX-27 | [ex_27_daf_grant_screening.rb](./ex_27_daf_grant_screening.rb)           | DAF grant-recommendation screening, with a stricter policy than EX-26 over identical data.              |
| EX-28 | [ex_28_crm_enrichment.rb](./ex_28_crm_enrichment.rb)                     | CRM sync keyed on EIN, where a `null` from the API never erases better customer data.                   |
| EX-29 | [ex_29_pre_disbursement_recheck.rb](./ex_29_pre_disbursement_recheck.rb) | Recheck immediately before a payout; a material change pauses it and both evidence sets are kept.       |
| EX-30 | [ex_30_portfolio_reverification.rb](./ex_30_portfolio_reverification.rb) | Scheduled bulk re-verification with a diff against the last run and an explainable audit trail.         |

### Originals

|                                          |                                       |
| ---------------------------------------- | ------------------------------------- |
| [quickstart.rb](./quickstart.rb)         | The shortest useful single check.     |
| [bulk.rb](./bulk.rb)                     | The shortest useful bulk check.       |
| [error_handling.rb](./error_handling.rb) | Rescuing by error class in one place. |

## Checking a live deployment

The examples above prove the SDK works. To prove a _deployment_ still matches the
documented contract — and to see any schema drift — run the live smoke test
instead. It skips nothing, and it reports per example file: one heading per
`ex-NN`, and under it every check that stands behind what that file claims.

```bash
PACTMAN_API_KEY=your_key bundle exec ruby scripts/smoke_live.rb <ein> <bulk-eins> <missing-ein>
```

It spends real quota. What it will cost is printed before the first request goes
out. `PACTMAN_BASE_URL` aims it at a deployment other than production.

## Shared helpers

[`lib/`](./lib) holds the small pieces the numbered examples share, so each file
stays on its own subject. None of it is part of the SDK.

|                                          |                                                                                                   |
| ---------------------------------------- | ------------------------------------------------------------------------------------------------- |
| [lib/client.rb](./lib/client.rb)         | Reads the key and builds a client — the distilled form of EX-01.                                  |
| [lib/print.rb](./lib/print.rb)           | Console formatting. Prints `<null>` and `<not returned>` differently, on purpose.                 |
| [lib/fixture_api.rb](./lib/fixture_api.rb) | Starts and stops the fixture API for scenario-based examples.                                   |
| [lib/api_date.rb](./lib/api_date.rb)     | Parses the API's `M/DD/YYYY h:mm:ss AM` timestamps with that format, rather than letting `Time.parse` guess. |
| [lib/matching.rb](./lib/matching.rb)     | Name and address comparison, used by EX-04, EX-11 and the workflows.                              |
| [lib/address.rb](./lib/address.rb)       | Structural address validation for EX-05 — USPS codes, ZIP-to-state, placeholders. Offline.        |
| [lib/irs_codes.rb](./lib/irs_codes.rb)   | Lookup tables with an unknown-value fallback, for codes the API returns without a description.    |
| [lib/screening.rb](./lib/screening.rb)   | Gathers findings into one comparable Hash for the workflow examples. Decides nothing.             |

## One thing every example repeats

The SDK reports what the API returned. It produces no `approved`, `eligible` or
`safe` verdict, and no predicate summarizing a source the API does not itself
express as a boolean. Whether an organization qualifies for a donation, a grant,
a match or a payout is a determination for your own legal, compliance and risk
policy — which is why the routing logic in these examples lives in the example,
never in the library.
