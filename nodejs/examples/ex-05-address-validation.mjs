/**
 * EX-05 — Validating the address the API returned.
 *
 * The response carries `address_line1`, `address_line2`, `city`, `state`,
 * `state_name` and `zip`. This example asks one question about them: is this
 * address well-formed and self-consistent enough to act on?
 *
 * Three outcomes, and the middle one is the point:
 *
 *   usable        every required component came back, and nothing contradicts
 *   incomplete    a required component was not returned — absence, not error
 *   inconsistent  the components came back and disagree with each other
 *
 * A record can be complete and wrong. `state` and `state_name` are two fields
 * for one fact, and a ZIP already encodes the state a third time, so an extract
 * that has been transcribed, merged or truncated can contradict itself while
 * every field passes a null check.
 *
 * Well-formed is not deliverable. Nothing here asks USPS whether mail arrives;
 * see the closing note for where that call would go.
 *
 * Run:  PACTMAN_API_KEY=... node examples/ex-05-address-validation.mjs
 */
import { FIXTURE_EINS, withFixtureApi } from './lib/fixture-api.mjs';
import { bullet, field, heading, note, render } from './lib/print.mjs';
import { ADDRESS_COMPONENTS, isUsable, validateAddress } from './lib/address.mjs';

/** One clean record, one with components missing, one that contradicts itself. */
const SUBJECTS = [
  { label: 'Complete record', ein: FIXTURE_EINS.publicCharity },
  { label: 'Sparse record — components not returned', ein: FIXTURE_EINS.sparseIdentity },
  { label: 'Complete record that disagrees with itself', ein: FIXTURE_EINS.inconsistentAddress },
];

/** Your policy, not the SDK's. This one refuses to treat absence as validity. */
function route(verdict) {
  switch (verdict) {
    case 'usable':
      return 'continue — the address is complete and self-consistent';
    case 'incomplete':
      return 'manual review — too little address data came back to act on';
    default:
      return 'manual review — the returned components contradict each other';
  }
}

const MARKS = { pass: '✓', fail: '✗', not_checkable: '·' };

await withFixtureApi(async client => {
  for (const subject of SUBJECTS) {
    const { nonprofit } = await client.nonprofits.check(subject.ein);

    if (!nonprofit) {
      console.log(`No record for ${subject.ein}.`);
      continue;
    }

    heading(`${subject.label} — ${nonprofit.organization_name} (${nonprofit.ein})`);

    // What came back, before any judgement. `<null>` and `<not returned>` print
    // differently here for the same reason they do everywhere else.
    for (const component of ADDRESS_COMPONENTS) {
      field(component, nonprofit[component], 16);
    }

    const { verdict, checks, missing, failures } = validateAddress(nonprofit);

    console.log('\n  checks:');

    for (const entry of checks) {
      // A check that could not run is marked apart from one that passed. An
      // unrunnable check has confirmed nothing about this address.
      bullet(
        `${MARKS[entry.outcome]} ${entry.label.padEnd(38)} ${entry.outcome.padEnd(14)}${entry.detail ?? ''}`.trimEnd(),
      );
    }

    console.log('');
    field('components not returned', missing.join(', ') || '<none>');
    field('checks failed', failures.map(entry => entry.id).join(', ') || '<none>');
    field('verdict', verdict);
    field('routed to', route(verdict));

    if (isUsable(verdict)) {
      // Only now is it reasonable to store this as the organization's address,
      // and even now it is the IRS filing address, not proof of an occupant.
      field('safe to persist as-is', 'yes — no component is missing or contradicted');
    }
  }
});

note(
  'Complete is not the same as correct, and correct is not the same as deliverable.\n' +
    'These checks are structural: they run offline, need no second credential, and\n' +
    'catch the damage that survives a null check. A deliverability verdict — USPS,\n' +
    'Lob, Smarty, Google Address Validation — is a network call with its own key,\n' +
    'and it belongs as one more check inside validateAddress(), not as a\n' +
    'replacement for these. Bear in mind what a failure there would mean: an IRS\n' +
    'filing address is often a PO box, an accountant or a registered agent, so a\n' +
    'deliverability miss is a fact about the mailbox, never about the charity.',
);
