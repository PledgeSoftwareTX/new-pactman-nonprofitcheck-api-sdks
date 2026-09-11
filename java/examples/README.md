# Examples

Runnable examples for the Pactman Nonprofit Check Plus Java SDK.

Every example is a class implementing `Example`, listed in
[`support/Catalog.java`](src/main/java/org/pactman/nonprofitcheckplus/examples/support/Catalog.java)
and run by [`Main`](src/main/java/org/pactman/nonprofitcheckplus/examples/Main.java).

## Running them

```bash
# Every example against the bundled fixture API. No key, no network.
# This is also part of `mvn verify`, so a stale example fails the build.
mvn -q verify

# Install the SDK into your local repository once, then run examples one by one.
mvn -q -DskipTests install
mvn -q -pl examples exec:java -Dexec.args="--list"
mvn -q -pl examples exec:java -Dexec.args="ex-10"
```

Against the real API, set your key:

```bash
PACTMAN_API_KEY=... mvn -q -pl examples exec:java -Dexec.args="ex-03 41-1787097"
```

`PACTMAN_BASE_URL` points any example at a different host — a sandbox, a proxy,
or your own mock.

## Where the data comes from

Some scenarios cannot be summoned on demand from the production API: a revoked
exemption, a possible OFAC match, a cross-source conflict, an HTTP 429, a
response carrying a field newer than this SDK. Examples that need one of those
run against [`FixtureApi`](../devtools/src/main/java/org/pactman/nonprofitcheckplus/devtools/FixtureApi.java),
a small in-process server that speaks the same envelope, auth, batch-limit,
bulk-matching and check-count semantics as the real service.

The records it serves are in
[`Fixtures.java`](../devtools/src/main/java/org/pactman/nonprofitcheckplus/devtools/Fixtures.java).
The EINs are illustrative and are not real organizations. Dates are generated
relative to today, so the freshness examples stay meaningful however long after
they were written they are run.

Both live in the `devtools` module rather than here, so the examples, the
stand-in server you can run yourself (`mvn -q -pl devtools exec:java
-Dexec.args="mock"`) and the live-drift checks all read one set of records. A
unit test holds the fixture responses against the same `response-contract.json`
the SDK ships, so the examples cannot end up rehearsing against a shape the real
service does not produce.

## The examples

### Getting started

| | |
| --- | --- |
| `quickstart` | The smallest useful lookup |
| `ex-01` | Secure client initialization, and proof the key reaches no diagnostic surface |
| `ex-02` | EIN normalization, and every value that is rejected locally |
| `ex-03` | Identity fields, and why "absent" and "null" are different answers |

### Comparing against the record

| | |
| --- | --- |
| `ex-04` | Comparing an applicant's typed name against the three names the IRS holds |
| `ex-05` | Address validation past a null check: placeholders and contradictions |

### Reading the sources

| | |
| --- | --- |
| `ex-06` | The Business Master File finding, and its three states |
| `ex-07` | Publication 78 listing and deductibility limits |
| `ex-08` | Automatic revocation, visible across three fields |
| `ex-09` | Revocation and reinstatement, which must be read together |
| `ex-10` | OFAC screening, and the four states it can be in |
| `ex-11` | A BMF and Publication 78 disagreement the API refuses to resolve |
| `ex-12` | Public charity versus private foundation |
| `ex-13` | Filing and exemption codes, and how to own a lookup table safely |
| `ex-14` | How old the findings actually are |

### Errors and edge cases

| | |
| --- | --- |
| `ex-15` | Malformed input fails locally, before a billable request |
| `ex-16` | A well-formed EIN the API has no record for |
| `ex-22` | HTTP 429, `Retry-After`, and a client-side ceiling |
| `ex-23` | What gets retried, and what never does |
| `ex-24` | Timeouts, and the two ways to cancel a call |
| `ex-25` | Reading fields this SDK version has never heard of |

### Bulk

| | |
| --- | --- |
| `ex-17` | Screening a batch in one request |
| `ex-18` | Request order, response order, and duplicate EINs |
| `ex-19` | A 200 that still reports failures |
| `ex-20` | The 50-EIN batch limit, and chunking on your own terms |
| `ex-21` | What `checkCount` means, and how to measure one request |

### End-to-end workflows

| | |
| --- | --- |
| `ex-26` | Onboarding: routing an application to a reviewer |
| `ex-27` | DAF grant screening: a stricter policy on the same evidence |
| `ex-28` | CRM enrichment without overwriting good data with nulls |
| `ex-29` | A pre-disbursement re-check that fails closed |
| `ex-30` | A scheduled portfolio sweep that produces a work queue |

## One thing every example repeats

None of this code decides whether an organization is legitimate, eligible, or
safe to pay. The SDK reports what the API returned; the examples show how to
read it. `ex-26`, `ex-27` and `ex-29` deliberately reach different conclusions
from overlapping evidence, because a donation platform, a donor-advised fund and
a payout gate have different obligations — and all three are right for their own.

The helper classes in
[`support/`](src/main/java/org/pactman/nonprofitcheckplus/examples/support)
— name matching, address checks, IRS code tables, screening summaries — are
example code, not part of the SDK, and are exactly the parts you should expect
to replace with your own policy.
