# Examples

Thirty runnable examples for the Salesforce SDK, matching `ex-01` – `ex-30` in
the Node, Python, Go, Java and .NET SDKs.

**They are Apex test classes, and that is not a compromise.** Apex has no
script runner: a `.apex` file executed with `sf apex run` cannot set a callout
mock, and without one an example cannot show you a revoked exemption, an OFAC
match, an HTTP 429 or a field newer than the SDK — production will not produce
any of those on request. `Test.setMock` is the only place those scenarios exist,
so the examples live where `Test.setMock` works. The upside is that every one of
them asserts what it claims, and CI runs all thirty on every push.

```bash
# every example, with its output in the debug log
sf apex run test --target-org my-scratch --test-level RunLocalTests \
  --result-format human --wait 20

# one example
sf apex run test --target-org my-scratch --class-names Ex10OfacScreening \
  --result-format human --wait 20
```

`examples-app` is a second, **unpackaged** directory in
[`sfdx-project.json`](../sfdx-project.json): `sf project deploy start` sends it
to a scratch org, and `sf package version create` leaves it out. Nothing here
ships to a subscriber.

## Reading the output

Each example writes to the debug log through
[`ExampleOutput`](./main/default/classes/ExampleOutput.cls). Run with
`--result-format human` and raise the Apex log level to `FINEST` to see it, or
open the test run in Developer Console.

The assertions are the part that runs unattended. An example that stops
demonstrating what it claims fails the Apex test run, rather than going stale in
a directory nobody opens.

## A note on the namespace

These examples call the SDK with bare class names — `new Client()`,
`Sources.getBmf(...)` — because `namespace` in `sfdx-project.json` is
deliberately empty and this is how the package's own tests are written.

A subscriber installing the managed package writes the same code with the
namespace prefix:

```apex
pactman.Client client = new pactman.Client();
pactman.BmfSource bmf = pactman.Sources.getBmf(result.nonprofit);
```

## The examples

### Getting started

|       |                                                                              |                                                                                                                                                 |
| ----- | ---------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------- |
| EX-01 | [Ex01SecureClientInit](./main/default/classes/Ex01SecureClientInit.cls)       | Where the credential lives, why Apex cannot read it, and the two configurations the SDK refuses.                                                |
| EX-02 | [Ex02EinNormalization](./main/default/classes/Ex02EinNormalization.cls)       | Every accepted spelling of an EIN and every rejected one, plus `Ein.chunk` and why batch count matters in Apex.                                 |
| EX-03 | [Ex03IdentityLookup](./main/default/classes/Ex03IdentityLookup.cls)           | The identity fields, and `has()` — the difference between a field returned as null and a field not returned at all.                             |

### Comparing and validating against the record

|       |                                                                            |                                                                                                    |
| ----- | -------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------- |
| EX-04 | [Ex04NameComparison](./main/default/classes/Ex04NameComparison.cls)        | Compare a submitted name against all three the API returns, without treating punctuation as fraud. |
| EX-05 | [Ex05AddressValidation](./main/default/classes/Ex05AddressValidation.cls)  | Validate the returned address structurally. Complete is not the same as correct.                   |

### Reading the sources

|       |                                                                                                |                                                                                                    |
| ----- | ---------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------- |
| EX-06 | [Ex06BmfStatus](./main/default/classes/Ex06BmfStatus.cls)                                      | The Business Master File finding, and why `bmf_status` is a `Boolean` with three states.           |
| EX-07 | [Ex07Pub78Deductibility](./main/default/classes/Ex07Pub78Deductibility.cls)                    | Publication 78 verification and the deductibility limit a donor actually feels.                    |
| EX-08 | [Ex08AutomaticRevocation](./main/default/classes/Ex08AutomaticRevocation.cls)                  | An automatic revocation, read across every source that reports it.                                 |
| EX-09 | [Ex09RevocationReinstatement](./main/default/classes/Ex09RevocationReinstatement.cls)          | Revocation and reinstatement read together, because one of them is current and one is history.     |
| EX-10 | [Ex10OfacScreening](./main/default/classes/Ex10OfacScreening.cls)                              | Four distinct OFAC outcomes — no match, match, null, and not screened at all.                      |
| EX-11 | [Ex11SourceConflict](./main/default/classes/Ex11SourceConflict.cls)                            | `irs_bmf_pub78_conflict` handled by recording both sources rather than picking one.                |
| EX-12 | [Ex12FoundationClassification](./main/default/classes/Ex12FoundationClassification.cls)        | Public charity versus private foundation, read from the descriptions the API supplies.             |
| EX-13 | [Ex13FilingExemptionMetadata](./main/default/classes/Ex13FilingExemptionMetadata.cls)          | Bare codes described through a local table with an unknown-value fallback.                         |
| EX-14 | [Ex14DataFreshness](./main/default/classes/Ex14DataFreshness.cls)                              | How old each finding is, and why `Datetime.parse` is the wrong tool for it.                        |

### Errors and edge cases

|       |                                                                                          |                                                                                                            |
| ----- | ---------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------- |
| EX-15 | [Ex15MalformedEin](./main/default/classes/Ex15MalformedEin.cls)                          | Malformed input rejected locally, proven by a mock that counts: no callout, no quota, no governor limit.    |
| EX-16 | [Ex16NotFound](./main/default/classes/Ex16NotFound.cls)                                  | A well-formed EIN with no record, and the same failure rendered for a structured log.                      |
| EX-22 | [Ex22RateLimit](./main/default/classes/Ex22RateLimit.cls)                                | HTTP 429, `Retry-After`, and why Apex surfaces it instead of waiting.                                      |
| EX-23 | [Ex23TransientRetries](./main/default/classes/Ex23TransientRetries.cls)                  | The one thing this SDK retries — a lost response, once — and everything it does not.                       |
| EX-24 | [Ex24TimeoutAndCancellation](./main/default/classes/Ex24TimeoutAndCancellation.cls)      | `TimeoutException` versus `NetworkException`, the platform ceilings, and why cancellation does not exist.   |
| EX-25 | [Ex25RawAndForwardCompat](./main/default/classes/Ex25RawAndForwardCompat.cls)            | Fields and an enum value this version has never heard of, readable without a package upgrade.               |

### Bulk

|       |                                                                                          |                                                                                                        |
| ----- | ---------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------ |
| EX-17 | [Ex17BulkScreening](./main/default/classes/Ex17BulkScreening.cls)                        | Screening a grantee list in one request — one callout instead of five.                                 |
| EX-18 | [Ex18BulkOrderAndDuplicates](./main/default/classes/Ex18BulkOrderAndDuplicates.cls)      | Why `byEin()` exists: the response neither keeps your order nor repeats a duplicate.                   |
| EX-19 | [Ex19BulkPartialSuccess](./main/default/classes/Ex19BulkPartialSuccess.cls)              | Mixed outcomes on one HTTP 200 with no exception, and a full input reconciliation.                     |
| EX-20 | [Ex20BulkBatchLimits](./main/default/classes/Ex20BulkBatchLimits.cls)                    | Empty and over-limit batches refused, `Ein.chunk` for the rest, and the 100-callout ceiling.           |
| EX-21 | [Ex21UsageTracking](./main/default/classes/Ex21UsageTracking.cls)                        | `checkCount` as a cumulative billing-cycle total — never a per-request size.                            |

### End-to-end workflows

|       |                                                                                            |                                                                                                    |
| ----- | ------------------------------------------------------------------------------------------ | -------------------------------------------------------------------------------------------------- |
| EX-26 | [Ex26OnboardingWorkflow](./main/default/classes/Ex26OnboardingWorkflow.cls)                | Donation-platform onboarding: route to proceed, or to a reviewer.                                  |
| EX-27 | [Ex27DafGrantScreening](./main/default/classes/Ex27DafGrantScreening.cls)                  | DAF grant screening — a stricter policy over identical data. Compare with EX-26.                   |
| EX-28 | [Ex28CrmEnrichment](./main/default/classes/Ex28CrmEnrichment.cls)                          | Enriching `Account` records without letting a null erase good data, in callout-then-DML order.      |
| EX-29 | [Ex29PreDisbursementRecheck](./main/default/classes/Ex29PreDisbursementRecheck.cls)        | A re-check in the path of a payment that fails closed when it cannot complete.                     |
| EX-30 | [Ex30PortfolioReverification](./main/default/classes/Ex30PortfolioReverification.cls)      | A scheduled sweep producing a work queue, and when to move it to Batch Apex.                       |

### A first read

Three shorter examples sit alongside the numbered set, matching `quickstart`,
`bulk` and `error-handling` in the other SDKs.

|                                                                     |                                                                  |
| ------------------------------------------------------------------- | ---------------------------------------------------------------- |
| [Quickstart](./main/default/classes/Quickstart.cls)                 | The smallest useful lookup, and three source findings.           |
| [BulkOverview](./main/default/classes/BulkOverview.cls)             | One request for a batch, with local validation and iteration.    |
| [ErrorHandlingOverview](./main/default/classes/ErrorHandlingOverview.cls) | Every failure turned into an action by type, never by message. |

## Where Apex genuinely differs

Four of these examples reach a different conclusion from their counterparts in
the other SDKs, because the platform leaves no choice. They are worth reading
even if you know the other SDKs well.

| Example | The other SDKs                                          | Apex                                                                                                                                       |
| ------- | ------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------ |
| EX-01   | Load a key from the environment; prove it never leaks.  | There is no key in Apex. The platform injects it from the External Credential, so there is no diagnostic surface to audit.                 |
| EX-22   | Wait `Retry-After` and retry; throttle client-side.     | Apex cannot sleep. `Retry-After` is surfaced on the exception, and `CheckQueueable` is where real backoff happens.                          |
| EX-23   | Retry transient 5xx with jittered exponential backoff.  | One immediate retry, for a single or bulk check that produced no response. Timeouts and HTTP errors are surfaced.                             |
| EX-24   | `AbortSignal` / context cancellation.                   | No cancellation primitive exists. What there is instead: a 120-second per-callout ceiling and a 120-second cumulative budget per transaction. |

## Shared helpers

Under [`main/default/classes`](./main/default/classes), alongside the examples.
None of it is part of the SDK.

|                                                                          |                                                                                                       |
| ------------------------------------------------------------------------ | ----------------------------------------------------------------------------------------------------- |
| [ExampleFixtures](./main/default/classes/ExampleFixtures.cls)            | The records every example runs against, and the EIN constants that name them.                          |
| [ExampleApiMock](./main/default/classes/ExampleApiMock.cls)              | A stand-in API with a cumulative check count, bulk set semantics, and control EINs for each failure.   |
| [ExampleOutput](./main/default/classes/ExampleOutput.cls)                | Debug-log formatting. Prints `<null>` and `<not returned>` differently, on purpose.                    |
| [ExampleDates](./main/default/classes/ExampleDates.cls)                  | Parses the API's display-formatted timestamps without depending on the running user's locale.          |
| [ExampleMatching](./main/default/classes/ExampleMatching.cls)            | Name comparison, used by EX-04 and the workflows.                                                      |
| [ExampleAddresses](./main/default/classes/ExampleAddresses.cls)          | Structural address validation for EX-05.                                                               |
| [ExampleIrsCodes](./main/default/classes/ExampleIrsCodes.cls)            | Lookup tables with an unknown-value fallback, for codes the API returns bare.                          |
| [ExampleScreening](./main/default/classes/ExampleScreening.cls)          | Gathers findings into one comparable list for the workflow examples. Decides nothing.                  |

### Why not `FixtureMock`?

The package ships [`FixtureMock`](../force-app/main/default/classes/FixtureMock.cls)
for **subscribers** to test their own code with, and it is the right tool for
that: two lines, one seeded EIN, done. Use it in your own tests.

`ExampleApiMock` exists because these examples need more than it offers — a
check count that actually moves between calls, bulk set-membership semantics,
and control EINs that produce a 429, a lost response and a timeout. It serves
the same records as the mock servers in the other five SDKs, so `ex-17` shows
the same numbers here as it does in Go.

## One thing every example repeats

The SDK reports what the API returned. It produces no `approved`, `eligible` or
`safe` verdict, and no boolean summarizing a source the API does not itself
express as a boolean. Whether an organization qualifies for a donation, a grant,
a match or a payout is a determination for your own legal, compliance and risk
policy — which is why the routing logic in these examples lives in the example,
never in the library.
