/**
 * EX-21 — Billing-cycle usage tracking.
 *
 * `nonprofit_check_count`, surfaced as `result.checkCount`, is the running total
 * of checks your account has consumed so far in the current billing cycle. It is
 * never the size of the request you just made.
 *
 * The test is one thing: fetch one nonprofit by EIN, and confirm the API sent
 * that counter as a JSON number. The SDK maps anything else to `null`, which
 * downstream is indistinguishable from "not reported", so the check reads the
 * uncoerced value off `raw`. This example exits non-zero when it is not a number.
 *
 * Run:  PACTMAN_API_KEY=... node examples/ex-21-usage-tracking.mjs [EIN]
 */
import { createClient } from './lib/client.mjs';
import { FIXTURE_EINS } from './lib/fixture-api.mjs';
import { field, heading, note } from './lib/print.mjs';

/** The JSON type of a value, in the vocabulary the response contract uses. */
function jsonTypeOf(value) {
  if (value === null) {
    return 'null';
  }

  if (Array.isArray(value)) {
    return 'array';
  }

  return typeof value === 'object' ? 'object' : typeof value;
}

const client = createClient();
const ein = process.argv[2] ?? FIXTURE_EINS.publicCharity;

const result = await client.nonprofits.check(ein);

// `checkCount` is `number | null`, and the SDK produces that `null` both for a
// counter the API sent as null and for one it sent as `"42"`. Only `raw`, which
// nothing has coerced, tells them apart.
const envelope = result.raw;
const returned =
  envelope !== null && typeof envelope === 'object' && 'nonprofit_check_count' in envelope;
const wireValue = returned ? envelope.nonprofit_check_count : undefined;
const wireType = returned ? jsonTypeOf(wireValue) : '<not returned>';

heading('nonprofit_check_count on the wire');
field('ein', ein);
field('wire type', wireType);
field('checkCount', result.checkCount);

note(
  'The counter is cumulative for the billing cycle and resets when a new one starts.\n' +
    'A bulk call for five EINs does not return 5 — it returns your cycle total.',
);

if (wireType !== 'number') {
  console.error(
    `\nnonprofit_check_count arrived as ${wireType}` +
      `${returned ? ` ${JSON.stringify(wireValue)}` : ''}, not a number, ` +
      'so checkCount reads null.',
  );
  process.exit(1);
}
