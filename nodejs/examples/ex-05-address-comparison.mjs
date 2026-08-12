/**
 * EX-05 — Applicant address comparison.
 *
 * Compares a submitted address against `address_line1`, `address_line2`, `city`,
 * `state`, `state_name` and `zip`.
 *
 * The point of this example is the third outcome. A component can agree, it can
 * disagree, or the API can have returned nothing for it — and the third is not
 * the first. An organization whose `zip` came back `null` has not confirmed your
 * applicant's ZIP code.
 *
 * Run:  PACTMAN_API_KEY=... node examples/ex-05-address-comparison.mjs
 */
import { createClient } from './lib/client.mjs';
import { field, heading, note, render } from './lib/print.mjs';
import { FIXTURE_EINS } from './lib/fixture-api.mjs';
import { compareAddressField, isAgreement, normalizeZip } from './lib/matching.mjs';

const client = createClient();

const applicants = [
  {
    label: 'Complete record, formatting differences only',
    ein: FIXTURE_EINS.publicCharity,
    address: {
      address_line1: '50 Lowell Avenue',
      address_line2: 'Apt 3B',
      city: 'Westfield',
      state: 'MA',
      state_name: 'Massachusetts',
      zip: '01085',
    },
  },
  {
    label: 'Sparse record — several components were not returned',
    ein: FIXTURE_EINS.sparseIdentity,
    address: {
      address_line1: 'PO Box 118',
      address_line2: null,
      city: 'Rockport',
      state: 'ME',
      state_name: 'Maine',
      zip: '04856',
    },
  },
];

const COMPONENTS = ['address_line1', 'address_line2', 'city', 'state', 'state_name', 'zip'];

for (const applicant of applicants) {
  const { nonprofit } = await client.nonprofits.check(applicant.ein);

  if (!nonprofit) {
    console.log(`No record for ${applicant.ein}.`);
    continue;
  }

  heading(applicant.label);

  const outcomes = {};

  for (const component of COMPONENTS) {
    // ZIP+4 versus ZIP5 is a formatting difference, so `zip` gets its own
    // normalizer. Everything else compares as a street-style line.
    const comparison = compareAddressField(
      applicant.address[component],
      nonprofit[component],
      component === 'zip' ? normalizeZip : undefined,
    );

    outcomes[component] = comparison.outcome;

    console.log(
      `  ${component.padEnd(16)} ${comparison.outcome.padEnd(14)}` +
        ` submitted=${render(comparison.submitted)}  returned=${render(comparison.returned)}`,
    );
  }

  const agreed = COMPONENTS.filter(component => isAgreement(outcomes[component]));
  const missing = COMPONENTS.filter(component => outcomes[component] === 'not_returned');
  const conflicting = COMPONENTS.filter(component => outcomes[component] === 'mismatch');

  field('\ncomponents agreeing', agreed.join(', ') || '<none>');
  field('components not returned', missing.join(', ') || '<none>');
  field('components conflicting', conflicting.join(', ') || '<none>');

  // Your policy decides what a partial address confirms. This one refuses to
  // treat absence as confirmation.
  const outcome = conflicting.length > 0
    ? 'manual review — a returned component disagrees with the applicant'
    : missing.length > 0
      ? 'manual review — too little address data was returned to confirm anything'
      : 'continue — every returned component agrees';

  field('routed to', outcome);
}

note(
  'Null is not a match. The SDK preserves it as null all the way through, so the\n' +
    'difference between "the IRS record says something else" and "the IRS record\n' +
    'says nothing" stays visible to whoever reviews the applicant.',
);
