/**
 * EX-15 — Malformed EIN rejected locally.
 *
 * Bad input never becomes a request. Every rejection below happens in-process,
 * so it costs no quota, no latency, and no rate-limit budget.
 *
 * The example counts outbound HTTP calls with an instrumented `fetch` to prove
 * the claim rather than assert it.
 *
 * Run:  PACTMAN_API_KEY=... node examples/ex-15-malformed-ein.mjs
 */
import {
  EIN_LENGTH,
  PactmanClient,
  PactmanValidationError,
  isValidEin,
} from '@pactmandev/nonprofit-check-plus';
import { requireApiKey } from './lib/client.mjs';
import { bullet, field, heading, note } from './lib/print.mjs';

let requestsSent = 0;

// A counting wrapper around the runtime's fetch. If any call below reaches the
// network, this number moves.
const countingFetch = (input, init) => {
  requestsSent += 1;

  return globalThis.fetch(input, init);
};

const client = new PactmanClient({
  apiKey: requireApiKey(),
  ...(process.env.PACTMAN_BASE_URL ? { baseUrl: process.env.PACTMAN_BASE_URL } : {}),
  fetch: countingFetch,
});

const BAD_SINGLE_INPUTS = [
  ['too few digits', '41178709'],
  ['too many digits', '4117870977'],
  ['letters', '41-178709A'],
  ['empty string', ''],
  ['whitespace only', '   '],
  ['null', null],
  ['undefined', undefined],
  ['a number, not a string', 411787097],
  ['unsupported punctuation', '41.1787097'],
  ['hyphen in the wrong place', '411-787097'],
  ['two hyphens', '41-178-7097'],
];

heading(`Single checks (EINs are ${EIN_LENGTH} digits, optionally hyphenated XX-XXXXXXX)`);

for (const [label, value] of BAD_SINGLE_INPUTS) {
  try {
    await client.nonprofits.check(value);
    console.log(`  ${label.padEnd(26)} UNEXPECTEDLY ACCEPTED`);
  } catch (error) {
    if (!(error instanceof PactmanValidationError)) {
      throw error;
    }

    // `issues` identifies the offending value, so a form can highlight the field
    // rather than showing a generic failure.
    const [issue] = error.issues;

    console.log(
      `  ${label.padEnd(26)} isValidEin=${String(isValidEin(value)).padEnd(6)}` +
        ` origin=${error.origin}  ${issue?.message ?? error.message}`,
    );
  }
}

heading('Bulk checks — every failure is reported at once, by index');

const BAD_BATCHES = [
  ['one bad entry', ['411787097', 'nope', '996589560']],
  ['several bad entries', ['1234', '411787097', '', null]],
  ['not an array', 'not-an-array'],
  ['empty array', []],
];

for (const [label, batch] of BAD_BATCHES) {
  try {
    await client.nonprofits.checkBulk(batch);
    console.log(`  ${label}: UNEXPECTEDLY ACCEPTED`);
  } catch (error) {
    if (!(error instanceof PactmanValidationError)) {
      throw error;
    }

    console.log(`\n  ${label}: ${error.message}`);

    for (const issue of error.issues) {
      bullet(`index ${issue.index}: ${JSON.stringify(issue.value)} — ${issue.message}`);
    }
  }
}

// One valid call, to show the counter is wired up and does move.
if (process.env.PACTMAN_BASE_URL) {
  await client.nonprofits.check('411787097').catch(() => {});
}

heading('Network activity');
field('HTTP requests sent', requestsSent);
field('expected', process.env.PACTMAN_BASE_URL ? '1 (the single valid call at the end)' : '0');

note(
  'Validation is about shape only. `isValidEin` returning true means the value\n' +
    'looks like an EIN — not that the organization exists, is exempt, or is the one\n' +
    'your applicant claims to be.',
);
