# Examples

Runnable examples for `Pactman.NonprofitCheckPlus`. Every one reads `PACTMAN_API_KEY`
from the environment — or from a `.env` beside the package, which is gitignored — and
contains no credentials.

```bash
cd dotnet
PACTMAN_API_KEY=your_key dotnet run --project examples/Pactman.NonprofitCheckPlus.Examples -- ex-01
dotnet run --project examples/Pactman.NonprofitCheckPlus.Examples -- --list
```

Run all of them against the bundled fixture API, which is what CI does:

```bash
dotnet run --project scripts/Pactman.NonprofitCheckPlus.Tools -- examples-smoke              # pass/fail only
EXAMPLES_VERBOSE=1 dotnet run --project scripts/Pactman.NonprofitCheckPlus.Tools -- examples-smoke   # with output
dotnet run --project scripts/Pactman.NonprofitCheckPlus.Tools -- examples-smoke ex-22 ex-23  # a subset
```

Unlike the other SDKs, where each example is its own file run as its own process, here
each example is a class implementing `IExample` in [Cases/](./Pactman.NonprofitCheckPlus.Examples/Cases/).
They are discovered by reflection, so adding one is all it takes for the runner and CI to
pick it up — and the smoke pass runs all 33 in one process against one fixture server
rather than starting 33 runtimes.

## Where each example runs

| Target                            | Examples                                       | |
| --------------------------------- | ---------------------------------------------- | - |
| Production, or `PACTMAN_BASE_URL` | `ex-01` – `ex-04`, `ex-06`, `ex-07`, `ex-13`, `ex-15`, `quickstart` | Ordinary lookups. Pass an EIN as the first argument where noted. |
| The bundled fixture API           | everything else                                | Needs a record or a response a live API will not produce on request: a revoked exemption, an OFAC match, an HTTP 429, an address that contradicts itself, a field newer than this SDK. |

Fixture-backed examples start the server themselves and shut it down on the way out. Set
`PACTMAN_BASE_URL` to point them somewhere else — which is exactly how the smoke runner
gives all of them one shared server. Fixture records live in
[Fixtures.cs](../scripts/Pactman.NonprofitCheckPlus.Dev/Fixtures.cs).

## The examples

### Getting started

|       | | |
| ----- | ------------------------ | - |
| `quickstart` | [Quickstart.cs](./Pactman.NonprofitCheckPlus.Examples/Cases/Quickstart.cs) | Check one EIN and read the result. |
| EX-01 | [Ex01SecureClientInit.cs](./Pactman.NonprofitCheckPlus.Examples/Cases/Ex01SecureClientInit.cs) | Load the key from the environment, pick an environment, set a finite timeout, build one reusable client — and prove the key reaches no log, no exception, no debug output. |
| EX-02 | [Ex02EinNormalization.cs](./Pactman.NonprofitCheckPlus.Examples/Cases/Ex02EinNormalization.cs) | A hyphenated, whitespace-padded EIN normalized to nine digits before the request, with the original kept for diagnostics. |
| EX-03 | [Ex03IdentityLookup.cs](./Pactman.NonprofitCheckPlus.Examples/Cases/Ex03IdentityLookup.cs) | EIN, name, AKA and Pactman profile URL, plus the raw envelope alongside the typed model. |

### Comparing and validating against the record

|       | | |
| ----- | ------------------------ | - |
| EX-04 | [Ex04NameComparison.cs](./Pactman.NonprofitCheckPlus.Examples/Cases/Ex04NameComparison.cs) | Compare a submitted name with `organization_name` and `organization_name_aka` without treating punctuation or abbreviation differences as fraud. |
| EX-05 | [Ex05AddressValidation.cs](./Pactman.NonprofitCheckPlus.Examples/Cases/Ex05AddressValidation.cs) | Validate the returned address structurally — present, self-consistent, or neither. Complete is not the same as correct. |

### Reading the sources

|       | | |
| ----- | ------------------------ | - |
| EX-06 | [Ex06BmfStatus.cs](./Pactman.NonprofitCheckPlus.Examples/Cases/Ex06BmfStatus.cs) | Every IRS Business Master File field on the response — status, identity, subsection, exemption, ruling, foundation. |
| EX-07 | [Ex07Pub78Deductibility.cs](./Pactman.NonprofitCheckPlus.Examples/Cases/Ex07Pub78Deductibility.cs) | Publication 78 verification and deductibility entries, with a donation policy applied in customer code. |
| EX-08 | [Ex08AutomaticRevocation.cs](./Pactman.NonprofitCheckPlus.Examples/Cases/Ex08AutomaticRevocation.cs) | An organization in the IRS Automatic Revocation data, flagged and recorded with its source fields. |
| EX-09 | [Ex09RevocationReinstatement.cs](./Pactman.NonprofitCheckPlus.Examples/Cases/Ex09RevocationReinstatement.cs) | Revocation and reinstatement dates kept separate, and the questions reinstatement does not answer. |
| EX-10 | [Ex10OfacScreening.cs](./Pactman.NonprofitCheckPlus.Examples/Cases/Ex10OfacScreening.cs) | Four distinct OFAC outcomes — no match, match, null, and not screened at all. |
| EX-11 | [Ex11SourceConflict.cs](./Pactman.NonprofitCheckPlus.Examples/Cases/Ex11SourceConflict.cs) | `irs_bmf_pub78_conflict` handled by recording both sources, not by picking one. |
| EX-12 | [Ex12FoundationClassification.cs](./Pactman.NonprofitCheckPlus.Examples/Cases/Ex12FoundationClassification.cs) | Organization types, foundation and subsection classification for a grantmaker or DAF display. |
| EX-13 | [Ex13FilingExemptionMetadata.cs](./Pactman.NonprofitCheckPlus.Examples/Cases/Ex13FilingExemptionMetadata.cs) | Filing and exemption codes preserved exactly, or mapped through documented tables with an unknown-value fallback. |
| EX-14 | [Ex14DataFreshness.cs](./Pactman.NonprofitCheckPlus.Examples/Cases/Ex14DataFreshness.cs) | Source timestamps, report date and request timing, feeding an application-owned re-review rule. |

### Errors and edge cases

|       | | |
| ----- | ------------------------ | - |
| `error-handling` | [ErrorHandlingOverview.cs](./Pactman.NonprofitCheckPlus.Examples/Cases/ErrorHandlingOverview.cs) | The whole taxonomy in one file: what to catch, and what each type carries. |
| EX-15 | [Ex15MalformedEin.cs](./Pactman.NonprofitCheckPlus.Examples/Cases/Ex15MalformedEin.cs) | A malformed EIN rejected before the request, spending nothing, naming the item that failed. |
| EX-16 | [Ex16NotFound.cs](./Pactman.NonprofitCheckPlus.Examples/Cases/Ex16NotFound.cs) | A well-formed EIN with no record — an answer, and never an automatic approval. |
| EX-22 | [Ex22RateLimit.cs](./Pactman.NonprofitCheckPlus.Examples/Cases/Ex22RateLimit.cs) | HTTP 429, the server's `Retry-After` honored automatically, and a client-side ceiling. |
| EX-23 | [Ex23TransientRetries.cs](./Pactman.NonprofitCheckPlus.Examples/Cases/Ex23TransientRetries.cs) | A 503 that clears on retry, and the statuses that are never retried however the policy is written. |
| EX-24 | [Ex24TimeoutsAndBudgets.cs](./Pactman.NonprofitCheckPlus.Examples/Cases/Ex24TimeoutsAndBudgets.cs) | A per-attempt deadline is not a budget for the call. A `CancellationToken` is, and the two failures stay distinct. |
| EX-25 | [Ex25RawAndForwardCompat.cs](./Pactman.NonprofitCheckPlus.Examples/Cases/Ex25RawAndForwardCompat.cs) | Fields, nested objects and enum values newer than this SDK, all readable without an upgrade. |

### Bulk

|       | | |
| ----- | ------------------------ | - |
| `bulk` | [BulkOverview.cs](./Pactman.NonprofitCheckPlus.Examples/Cases/BulkOverview.cs) | The bulk endpoint end to end: send, index, account, dedupe. |
| EX-17 | [Ex17BulkScreening.cs](./Pactman.NonprofitCheckPlus.Examples/Cases/Ex17BulkScreening.cs) | Screening a grantee list, iterating organization-level results and reading the response envelope. |
| EX-18 | [Ex18BulkOrderAndDuplicates.cs](./Pactman.NonprofitCheckPlus.Examples/Cases/Ex18BulkOrderAndDuplicates.cs) | Why the response is a set and not a row-for-row answer, shown by pairing it wrongly first. |
| EX-19 | [Ex19BulkPartialSuccess.cs](./Pactman.NonprofitCheckPlus.Examples/Cases/Ex19BulkPartialSuccess.cs) | HTTP 200 carrying item-level failures, and accounting for every input. |
| EX-20 | [Ex20BulkBatchLimits.cs](./Pactman.NonprofitCheckPlus.Examples/Cases/Ex20BulkBatchLimits.cs) | The 50-EIN ceiling, why the SDK will not chunk for you, and how to chunk deliberately. |
| EX-21 | [Ex21UsageTracking.cs](./Pactman.NonprofitCheckPlus.Examples/Cases/Ex21UsageTracking.cs) | `CheckCount` as a billing-cycle total, and costing one request by the delta between two. |

### End-to-end workflows

|       | | |
| ----- | ------------------------ | - |
| EX-26 | [Ex26OnboardingWorkflow.cs](./Pactman.NonprofitCheckPlus.Examples/Cases/Ex26OnboardingWorkflow.cs) | One applicant end to end: validate, look up, read every source, route, and record the evidence. |
| EX-27 | [Ex27DafGrantScreening.cs](./Pactman.NonprofitCheckPlus.Examples/Cases/Ex27DafGrantScreening.cs) | DAF grant screening, including the classification that decides whether expenditure responsibility applies. |
| EX-28 | [Ex28CrmEnrichment.cs](./Pactman.NonprofitCheckPlus.Examples/Cases/Ex28CrmEnrichment.cs) | Mapping a response to a CRM row without flattening "returned null" into "not returned". |
| EX-29 | [Ex29PreDisbursementRecheck.cs](./Pactman.NonprofitCheckPlus.Examples/Cases/Ex29PreDisbursementRecheck.cs) | Re-checking at payment time and diffing against what approval recorded. |
| EX-30 | [Ex30PortfolioReverification.cs](./Pactman.NonprofitCheckPlus.Examples/Cases/Ex30PortfolioReverification.cs) | A scheduled sweep: chunked, throttled, tolerant of a failed batch, reporting only what moved. |

## Fixture EINs

Named in [Fixtures.cs](../scripts/Pactman.NonprofitCheckPlus.Dev/Fixtures.cs) so no example
hard-codes a bare number. They are illustrative and are not real organizations.

| Scenario | |
| -------- | - |
| `PublicCharity`, `PublicCharitySecond` | Clean 501(c)(3) public charities, every source returned. |
| `PrivateFoundation`                    | Different foundation, filing and deductibility codes. |
| `SparseIdentity`                       | Most optional identity fields null; OFAC not returned at all. |
| `InconsistentAddress`                  | Address fields present and contradicting each other. |
| `StaleData`                            | Nothing adverse, every source well out of date. |
| `Revoked`, `Reinstated`                | Automatic revocation, with and without reinstatement. |
| `OfacMatch`, `OfacUnavailable`         | A possible SDN match, and OFAC returning nothing. |
| `Conflicted`                           | BMF and Publication 78 disagree. |
| `FutureFields`                         | Fields and an enum value newer than this SDK. |
| `NoRecord`                             | Well-formed, but no record exists. |

Three control EINs make the server misbehave on purpose: `RateLimited` answers 429 with
`Retry-After: 1`, `TransientFailure` answers 503 twice then succeeds, and `Slow` holds the
response open so a short timeout expires.
