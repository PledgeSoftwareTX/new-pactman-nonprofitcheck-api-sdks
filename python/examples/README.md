# Examples

Runnable examples for `pactman-nonprofit-check-plus`. Every one reads
`PACTMAN_API_KEY` from the environment and contains no credentials.

```bash
pip install -e .                                # examples import the package by name
PACTMAN_API_KEY=your_key python examples/ex_01_secure_client_init.py
```

Run all of them against the bundled fixture API, which is what CI does:

```bash
python scripts/run_examples_against_mock.py                 # all examples, pass/fail only
EXAMPLES_VERBOSE=1 python scripts/run_examples_against_mock.py   # with their output
python scripts/run_examples_against_mock.py ex_22 ex_23          # a subset
```

## Where each example runs

| Target                            | Examples                   |                                                                                                                                                   |
| --------------------------------- | -------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------- |
| Production, or `PACTMAN_BASE_URL` | `ex_01` – `ex_04`, `ex_06`, `ex_07`, `ex_15` | Ordinary lookups. Pass an EIN as the first argument where noted.                                                                                   |
| The bundled fixture API           | everything else            | Needs a record or a response a live API will not produce on request: a revoked exemption, an OFAC match, an HTTP 429, an address that contradicts itself, a field newer than this SDK. |

Fixture-backed examples start [`scripts/mock_server.py`](../scripts/mock_server.py)
themselves and shut it down on the way out. Set `PACTMAN_BASE_URL` to point them
somewhere else. Fixture records live in [`scripts/fixtures.py`](../scripts/fixtures.py).

## The examples

### Getting started

|       |                                                                |                                                                                                                                                                           |
| ----- | -------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| EX-01 | [ex_01_secure_client_init.py](./ex_01_secure_client_init.py)   | Load the key from the environment, pick an environment, set a finite timeout, build one reusable client — and prove the key reaches no log, no exception, no debug output. |
| EX-02 | [ex_02_ein_normalization.py](./ex_02_ein_normalization.py)     | A hyphenated, whitespace-padded EIN normalized to nine digits before the request, with the original kept for diagnostics.                                                  |
| EX-03 | [ex_03_identity_lookup.py](./ex_03_identity_lookup.py)         | EIN, name, AKA and Pactman profile URL, plus the raw envelope alongside the typed model.                                                                                   |

### Comparing and validating against the record

|       |                                                                |                                                                                                                                                 |
| ----- | -------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------- |
| EX-04 | [ex_04_name_comparison.py](./ex_04_name_comparison.py)         | Compare a submitted name with `organization_name` and `organization_name_aka` without treating punctuation or abbreviation differences as fraud. |
| EX-05 | [ex_05_address_validation.py](./ex_05_address_validation.py)   | Validate the returned address structurally — present, self-consistent, or neither. Complete is not the same as correct.                         |

### Reading the sources

|       |                                                                              |                                                                                                                    |
| ----- | ---------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------- |
| EX-06 | [ex_06_bmf_status.py](./ex_06_bmf_status.py)                                 | Every IRS Business Master File field on the response — status, identity, subsection, exemption, ruling, foundation. |
| EX-07 | [ex_07_pub78_deductibility.py](./ex_07_pub78_deductibility.py)               | Publication 78 verification and deductibility entries, with a donation policy applied in customer code.            |
| EX-08 | [ex_08_automatic_revocation.py](./ex_08_automatic_revocation.py)             | An organization in the IRS Automatic Revocation data, flagged and recorded with its source fields.                 |
| EX-09 | [ex_09_revocation_reinstatement.py](./ex_09_revocation_reinstatement.py)     | Revocation and reinstatement dates kept separate, and the questions reinstatement does not answer.                 |
| EX-10 | [ex_10_ofac_screening.py](./ex_10_ofac_screening.py)                         | Four distinct OFAC outcomes — no match, match, null, and not screened at all.                                      |
| EX-11 | [ex_11_source_conflict.py](./ex_11_source_conflict.py)                       | `irs_bmf_pub78_conflict` handled by recording both sources, not by picking one.                                    |
| EX-12 | [ex_12_foundation_classification.py](./ex_12_foundation_classification.py)   | Organization types, foundation and subsection classification for a grantmaker or DAF display.                      |
| EX-13 | [ex_13_filing_exemption_metadata.py](./ex_13_filing_exemption_metadata.py)   | Filing and exemption codes preserved exactly, or mapped through documented tables with an unknown-value fallback.  |
| EX-14 | [ex_14_data_freshness.py](./ex_14_data_freshness.py)                         | Source timestamps, report date and request timing, feeding an application-owned re-review rule.                    |

### Errors and edge cases

|       |                                                                            |                                                                                                                      |
| ----- | -------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------- |
| EX-15 | [ex_15_malformed_ein.py](./ex_15_malformed_ein.py)                         | Every malformed shape rejected locally, with an instrumented transport proving no request was sent.                  |
| EX-16 | [ex_16_not_found.py](./ex_16_not_found.py)                                 | A well-formed EIN with no record: `PactmanNotFoundError`, sanitized diagnostics, and why bulk behaves differently.   |
| EX-22 | [ex_22_rate_limit.py](./ex_22_rate_limit.py)                               | HTTP 429, `Retry-After`, bounded retries, a client-side rate ceiling and a bounded worker pool.                      |
| EX-23 | [ex_23_transient_retries.py](./ex_23_transient_retries.py)                 | Transient 5xx and connection failures retried with jittered backoff; auth, validation and not-found never retried.   |
| EX-24 | [ex_24_timeout_and_cancellation.py](./ex_24_timeout_and_cancellation.py)   | `PactmanTimeoutError` and asyncio cancellation kept distinguishable, with no work left running.                      |
| EX-25 | [ex_25_raw_and_forward_compat.py](./ex_25_raw_and_forward_compat.py)       | An approved fixture from a newer API version: unknown fields and an unknown enum value, both readable, neither fatal. |

### Bulk

|       |                                                                              |                                                                                                                                          |
| ----- | ---------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------ |
| EX-17 | [ex_17_bulk_screening.py](./ex_17_bulk_screening.py)                         | Screening a grantee list, iterating organization-level results and reading the response envelope.                                        |
| EX-18 | [ex_18_bulk_order_and_duplicates.py](./ex_18_bulk_order_and_duplicates.py)   | Response order does not follow request order, duplicates collapse in the response but still bill, and usage is read rather than inferred. |
| EX-19 | [ex_19_bulk_partial_success.py](./ex_19_bulk_partial_success.py)             | Mixed outcomes on one HTTP 200: usable records, item-level errors, and a full input reconciliation.                                      |
| EX-20 | [ex_20_bulk_batch_limits.py](./ex_20_bulk_batch_limits.py)                   | Empty and over-limit batches rejected against `MAX_BULK_EINS`, plus chunking a larger list yourself.                                     |
| EX-21 | [ex_21_usage_tracking.py](./ex_21_usage_tracking.py)                         | `nonprofit_check_count` as a cumulative billing-cycle total that resets each cycle — never a per-request size.                           |

### End-to-end workflows

|       |                                                                            |                                                                                                        |
| ----- | -------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------ |
| EX-26 | [ex_26_onboarding_workflow.py](./ex_26_onboarding_workflow.py)             | Donation-platform onboarding: collect, check, inspect every source, route to approve, reject or review. |
| EX-27 | [ex_27_daf_grant_screening.py](./ex_27_daf_grant_screening.py)             | DAF grant-recommendation screening, with a stricter policy than EX-26 over identical data.             |
| EX-28 | [ex_28_crm_enrichment.py](./ex_28_crm_enrichment.py)                       | CRM sync keyed on EIN, where a null from the API never erases better customer data.                    |
| EX-29 | [ex_29_pre_disbursement_recheck.py](./ex_29_pre_disbursement_recheck.py)   | Recheck immediately before a payout; a material change pauses it and both evidence sets are kept.      |
| EX-30 | [ex_30_portfolio_reverification.py](./ex_30_portfolio_reverification.py)   | Scheduled bulk re-verification with a diff against the last run and an explainable audit trail.        |

### Originals

|                                                    |                                             |
| -------------------------------------------------- | ------------------------------------------- |
| [quickstart.py](./quickstart.py)                   | The shortest useful single check.           |
| [bulk.py](./bulk.py)                               | The shortest useful bulk check.             |
| [error_handling.py](./error_handling.py)           | Branching on error type in one place.       |
| [async_concurrent.py](./async_concurrent.py)       | The async client, with concurrent lookups.  |

## Checking a live deployment

The examples above prove the SDK works against the bundled fixture API. To point
them at a real deployment instead, set `PACTMAN_BASE_URL` — the fixture server is
then never started, and every example runs against that host:

```bash
PACTMAN_API_KEY=your_key \
PACTMAN_BASE_URL=https://entities.pactman.org \
  python scripts/run_examples_against_mock.py ex_01 ex_02 ex_03
```

This spends real quota, one billable check per lookup, so name the examples you
want rather than running all of them.

To prove a deployment still matches the documented contract — and to see any
schema drift — run the live smoke test instead. It takes no options and skips
nothing, and it reports per example file: one heading per `ex-NN`, and under it
every check that stands behind what that file claims.

```bash
PACTMAN_API_KEY=your_key python scripts/smoke_live.py
```

It spends real quota too. What it will cost is printed before the first request
goes out, and `PACTMAN_BASE_URL` aims it at a deployment other than production.

## Shared helpers

[`lib/`](./lib) holds the small pieces the numbered examples share, so each file
stays on its own subject. None of it is part of the SDK.

|                                                |                                                                                                |
| ---------------------------------------------- | ---------------------------------------------------------------------------------------------- |
| [lib/client.py](./lib/client.py)               | Reads the key and builds a client — the distilled form of EX-01.                               |
| [lib/print.py](./lib/print.py)                 | Console formatting. Prints `<null>` and `<not returned>` differently, on purpose.              |
| [lib/fixture_api.py](./lib/fixture_api.py)     | Starts and stops the fixture API for scenario-based examples.                                  |
| [lib/matching.py](./lib/matching.py)           | Name and address comparison, used by EX-04, EX-11 and the workflows.                           |
| [lib/address.py](./lib/address.py)             | Structural address validation for EX-05 — USPS codes, ZIP-to-state, placeholders. Offline.     |
| [lib/irs_codes.py](./lib/irs_codes.py)         | Lookup tables with an unknown-value fallback, for codes the API returns without a description. |
| [lib/screening.py](./lib/screening.py)         | Gathers findings into one comparable object for the workflow examples. Decides nothing.        |

### Null versus not returned

JavaScript gets that distinction free from `null` versus `undefined`. Python does
not, so [`lib/print.py`](./lib/print.py) supplies a sentinel:

```python
from lib.print import NOT_RETURNED, pick, render

pick(nonprofit, "zip")       # None if the API sent null, NOT_RETURNED if absent
render(None)                 # "<null>"
render(NOT_RETURNED)         # "<not returned>"
```

Collapsing the two into `None` is how a missing value quietly becomes a match —
see EX-05 and EX-10 for what that costs.

## One thing every example repeats

The SDK reports what the API returned. It produces no `approved`, `eligible` or
`safe` verdict, and no boolean summarizing a source the API does not itself
express as a boolean. Whether an organization qualifies for a donation, a grant,
a match or a payout is a determination for your own legal, compliance and risk
policy — which is why the routing logic in these examples lives in the example,
never in the library.
