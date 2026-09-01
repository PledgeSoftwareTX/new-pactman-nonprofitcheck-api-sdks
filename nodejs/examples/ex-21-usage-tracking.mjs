/**
 * EX-21 — Billing-cycle usage tracking.
 *
 * `nonprofit_check_count`, surfaced as `result.checkCount`, is the running total
 * of checks your account has consumed so far in the current billing cycle. It is
 * never the size of the request you just made.
 *
 * The test is one thing: the API sends that counter as a JSON number. The SDK
 * maps anything else to `null`, which downstream is indistinguishable from "not
 * reported", so the check reads the uncoerced value off `raw`. This example
 * exits non-zero when any response fails it.
 *
 * Run:  PACTMAN_API_KEY=... node examples/ex-21-usage-tracking.mjs
 */
import { FIXTURE_EINS, withFixtureApi } from './lib/fixture-api.mjs';
import { bullet, field, heading, note } from './lib/print.mjs';

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

/**
 * How `nonprofit_check_count` arrived, before this SDK read it.
 *
 * `checkCount` is `number | null`, and the SDK produces that `null` both for a
 * counter the API sent as null and for one it sent as `"42"`. Only `raw`, which
 * nothing has coerced, tells them apart.
 */
function wireCheckCount(result) {
  const envelope = result.raw;

  if (envelope === null || typeof envelope !== 'object' || !('nonprofit_check_count' in envelope)) {
    return '<not returned>';
  }

  const value = envelope.nonprofit_check_count;
  const type = jsonTypeOf(value);

  return type === 'number' ? 'number' : `${type} ${JSON.stringify(value)}`;
}

const samples = await withFixtureApi(async client => {
  const responses = [
    ['single check', await client.nonprofits.check(FIXTURE_EINS.publicCharity)],
    ['single check', await client.nonprofits.check(FIXTURE_EINS.publicCharitySecond)],
    [
      'bulk check of 3',
      await client.nonprofits.checkBulk([
        FIXTURE_EINS.publicCharity,
        FIXTURE_EINS.publicCharitySecond,
        FIXTURE_EINS.privateFoundation,
      ]),
    ],
    [
      'bulk with a miss',
      await client.nonprofits.checkBulk([FIXTURE_EINS.revoked, FIXTURE_EINS.noRecord]),
    ],
  ];

  return responses.map(([label, result]) => ({
    label,
    wire: wireCheckCount(result),
    checkCount: result.checkCount,
  }));
});

heading('nonprofit_check_count on the wire');
console.log(`  ${'request'.padEnd(20)} ${'wire type'.padEnd(20)} checkCount`);

for (const sample of samples) {
  console.log(`  ${sample.label.padEnd(20)} ${sample.wire.padEnd(20)} ${sample.checkCount}`);
}

const mistyped = samples.filter(sample => sample.wire !== 'number');

heading('Verdict');
field('responses inspected', samples.length);
field('sent as a JSON number', samples.length - mistyped.length);

for (const sample of mistyped) {
  bullet(`${sample.label}: the API sent ${sample.wire}, so checkCount reads null`);
}

note(
  'The counter is cumulative for the billing cycle and resets when a new one starts.\n' +
    'A bulk call for five EINs does not return 5 — it returns your cycle total.',
);

if (mistyped.length > 0) {
  console.error(
    `\n${mistyped.length} of ${samples.length} responses did not send ` +
      'nonprofit_check_count as a number.',
  );
  process.exit(1);
}
