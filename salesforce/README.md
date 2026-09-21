# Pactman Nonprofit Check Plus — Salesforce (Apex)

Official Salesforce client for the **Pactman Nonprofit Check Plus API**: look up
US nonprofits by EIN and read the IRS and OFAC findings behind the result.

Distributed as a **second-generation managed package**, not through a registry.
Subscriber orgs install it from a package install URL; there is no `npm install`
equivalent.

> **Status: not yet deployed.** Every class here was written against the Node
> SDK's contract, and the offline checks pass — `npm run check` parses all of it
> with the Apex grammar, resolves every reference the examples make against the
> SDK's declared members, and confirms version and contract parity. But the
> machine it was authored on has no Salesforce CLI: nothing has been deployed to
> a scratch org, no Apex test has run, and the Named Credential metadata has not
> been round-tripped. Treat the first `sf project deploy start` as the real first
> compile, and expect it to find things a grammar cannot — type inference,
> governor limits, and whether `Test.setMock` behaves as the examples assume.

---

## Setup

Two things, once per org.

**1. Put the API key in the External Credential.** The package ships a Named
Credential (`Pactman_Nonprofit_Check`) backed by an External Credential
(`Pactman_API_Key`). In Setup → Named Credentials → External Credentials, open
`Pactman API Key`, add a Principal named `PactmanPrincipal`, and set its
`ApiKey` authentication parameter to your key.

**2. Assign the permission set.** `Pactman Nonprofit Check User` grants the Apex
classes and the credential principal the callout authenticates as. Without it,
callouts fail with a 401 even though the key is correct.

The key never appears in Apex. It is stored encrypted by the platform and
injected into the `Authorization` header at callout time, which is why this SDK
has no `apiKey` option and why it cannot leak through a debug log or a
serialized client.

## Quickstart

```apex
pactman.Client client = new pactman.Client();
pactman.SingleCheckResult result = client.nonprofits.check('41-1787097');

System.debug(result.nonprofit.organization_name);
System.debug(result.nonprofit.pub78_verified);
System.debug(result.checkCount);   // checks consumed this billing cycle
```

Field names mirror the wire format exactly, so what you read in the Pactman API
reference is what you access in code. That is why the accessors are `snake_case`
rather than Apex's usual camelCase — there is no rename table to keep in sync,
and `nonprofit.get('a_field_we_add_next_quarter')` keeps working without a
package upgrade.

Ask `has()` when the difference between "the API returned null" and "the API did
not return this field" matters. It usually does:

```apex
if (result.nonprofit.has('ofac_status')) {
    // The API has an OFAC opinion, even if it is null.
}
```

`ofac_status` is prose, not a flag. Read it or show it to a reviewer; do not
pattern-match it into a boolean.

### Grouped source views

```apex
pactman.Pub78Source pub78 = pactman.Sources.getPub78(result.nonprofit);
pactman.BmfSource   bmf   = pactman.Sources.getBmf(result.nonprofit);
```

These are projections, not derivations — every key is copied 1:1 from a field the
API returned. `null` means the API returned nothing at all for that source, which
is not the same as `pub78_verified == false`.

## Bulk

Up to 50 EINs per request. The API matches by set membership, so the response is
not ordered to match your input and a repeated EIN comes back once — index by
EIN rather than pairing positionally.

```apex
pactman.BulkCheckResult result = client.nonprofits.checkBulk(eins);

Map<String, pactman.Nonprofit> found = result.byEin();
System.debug(result.notFoundEins);   // 200, not an error
```

Batches are not split automatically — silently chunking would misreport how much
quota a call consumed. Split explicitly with `pactman.Ein.chunk(eins)`, and see
the governor limits below before you loop over the batches.

## Running checks from a trigger

Callouts are illegal from a trigger and after DML in the same transaction, which
is exactly where verification usually belongs. Use the Queueable:

```apex
public class VerifyAccounts implements pactman.CheckQueueable.Handler {
    public void handle(pactman.BulkCheckResult result) { /* write results back */ }
    public void handleFailure(pactman.PactmanException error) {
        System.debug(pactman.Errors.toMap(error));
    }
}

System.enqueueJob(new pactman.CheckQueueable(eins, new VerifyAccounts()));
```

It batches at 50, chains itself until the list is done, and re-enqueues with a
delay when the API rate-limits — the only real backoff Apex offers.

## Errors

Every failure is a `pactman.PactmanException` carrying a stable category and an
origin. Branch on the type or the category, never on message text.

```apex
try {
    client.nonprofits.check(ein);
} catch (pactman.ValidationException e) {
    // Local. No callout was made; e.issues names each bad value by index.
} catch (pactman.RateLimitException e) {
    // e.retryAfterSeconds, when the server sent one.
} catch (pactman.PactmanException e) {
    System.debug(pactman.Errors.toMap(e));
}
```

`pactman.Errors.wireValue(e.category)` returns the same string the Node, Python
and PHP SDKs log for the same failure — `bad_request`, `rate_limit`, and so on.

## Testing your own code

Subscriber orgs cannot make callouts in tests either, and cannot mock this SDK's
internal HTTP layer across a namespace boundary. So the package ships a mock:

```apex
@IsTest
static void verifiesAKnownNonprofit() {
    Test.setMock(HttpCalloutMock.class,
        new pactman.FixtureMock().withOrganization('41-1787097'));

    Test.startTest();
    pactman.SingleCheckResult result = new pactman.Client().nonprofits.check('41-1787097');
    Test.stopTest();

    Assert.areEqual('411787097', result.nonprofit.ein);
}
```

Seed the EINs your test expects to resolve; an unseeded EIN comes back as a 404
for a single check and in `notFoundEins` for a bulk check, exactly as the live
API reports it. `withStatus(429).withHeader('Retry-After', '30')` reproduces a
rate limit, and `withBody(...)` lets you test a malformed response.

## How this SDK differs from the others

Four places where Apex forced a real divergence, rather than a stylistic one.

**No `apiKey` option.** The other SDKs take the key as a constructor argument
and work to keep it out of logs. Salesforce already has an encrypted,
admin-managed store, so the key lives there and Apex never sees it.

**No exponential backoff.** Apex has no sleep primitive, and a busy-wait loop
burns the 10-second synchronous CPU limit and takes the transaction down. So:
a callout that returns no response at all is retried once, immediately, for a
single check and a bulk check alike, as the other SDKs retry a transport failure
on either endpoint; timeouts and HTTP errors are never retried in-transaction. `Retry-After` is surfaced on the exception, and
`CheckQueueable` is where real backoff happens.

**No client-side rate limiter.** `maxRequestsPerSecond` in the other SDKs is
implemented with sleep. Rather than ship a version that does not throttle, it is
omitted.

**Map-backed models.** `JSON.deserialize` into a typed Apex class rejects
attributes the class does not declare, and production already omits fields the
contract lists. So responses are decoded untyped and read through typed
accessors over the raw map — the same forward-compatibility the Node SDK gets
from an index signature.

## Governor limits

- **100 callouts per transaction**, and **120 seconds of cumulative callout
  time**. The timeout is what usually binds first. The SDK refuses to send with
  a clear message when the budget is exhausted, rather than letting a bare
  governor limit surface.
- **A single callout is capped at 120 seconds**, so `withTimeoutMs` refuses
  anything higher up front.
- **Queueable chaining** is one job deep per transaction; `CheckQueueable`
  reports a failure rather than silently dropping EINs when it cannot enqueue.

For volumes beyond a few thousand EINs, drive `checkBulk` from Batch Apex with
`Database.AllowsCallouts` rather than chaining Queueables.

## Examples

Thirty worked examples live in [`examples-app/`](./examples-app), matching
`ex-01` – `ex-30` in the Node, Python, Go, Java and .NET SDKs: client setup,
every source on a record, each error category, bulk semantics and five
end-to-end workflows. [`examples-app/README.md`](./examples-app/README.md) lists
what each one demonstrates.

They are Apex test classes, because `Test.setMock` is the only context in which
a revoked exemption, an OFAC match or an HTTP 429 can be produced on demand — so
every example asserts what it claims, and the whole set runs on every push.

```bash
sf apex run test --target-org pactman-dev --test-level RunLocalTests \
  --result-format human --wait 20
```

`examples-app` is unpackaged: a scratch org gets it, a subscriber does not.

Four of them reach different conclusions from their counterparts elsewhere,
because the platform leaves no choice — no readable credential (EX-01), no
sleep (EX-22, EX-23) and no cancellation (EX-24). Those are the ones to read
first if you already know another Pactman SDK.

## Development

```bash
npm install     # the offline checks below; not part of the package
sf org create scratch --definition-file config/project-scratch-def.json --alias pactman-dev --set-default
sf project deploy start
sf apex run test --test-level RunLocalTests --code-coverage --result-format human
npm run check
```

`npm run check` runs two things that need no org, and CI runs both before it
tries to create one:

- `scripts/check-parity.mjs` — the CI equivalent of the version and contract
  tests the other SDKs run in-process. Apex cannot read `sfdx-project.json` at
  runtime, so the assertions that `SdkVersion.VERSION` matches the package
  version and that `Nonprofit.cls` declares exactly the contract's fields live
  in CI instead.
- `scripts/check-apex.mjs` — parses every `.cls` with the Apex grammar and
  resolves every `Type.member` reference in the examples against what the SDK
  actually declares. A scratch org is the only real Apex compiler; this is the
  part of it that runs in four seconds. It is what catches a method named after
  a reserved word, which reads perfectly and does not parse.

`namespace` in `sfdx-project.json` is deliberately empty. Set it once the
namespace is registered and linked to the Dev Hub; scratch-org development works
without it.

### Before the first release

A managed package's `global` surface is permanent — a `global` class, method or
field can never be removed once a subscriber has installed a released version.
Beta versions are fully mutable, so do all API-surface design in beta and
promote only when the surface is one you are prepared to keep.

Note that `public` in a managed package is namespace-private and invisible to
subscribers; it is `global` that is forever, and `@deprecated` applies only to
`global` members.

## License

MIT — see [../LICENSE](../LICENSE).
