/**
 * EX-04 — Applicant name comparison.
 *
 * An applicant types a name during onboarding. The API returns the name IRS
 * records hold, plus an alternate name when one exists. Punctuation, casing and
 * abbreviation differences are normal; they are not evidence of fraud.
 *
 * The SDK deliberately has no `namesMatch()`. What counts as a match is your
 * policy, so the comparison lives here, in customer code.
 *
 * Run:  PACTMAN_API_KEY=... node examples/ex-04-name-comparison.mjs
 */
import { createClient } from './lib/client.mjs';
import { bullet, field, heading, note } from './lib/print.mjs';
import { FIXTURE_EINS } from './lib/fixture-api.mjs';
import { compareName, isAgreement } from './lib/matching.mjs';

const client = createClient();

// Three applicants against the same organization: a formatting difference, an
// abbreviation difference, and a genuinely different name.
const applicants = [
  { ein: FIXTURE_EINS.publicCharity, legalName: 'Meals Today Example Nonprofit' },
  { ein: FIXTURE_EINS.publicCharity, legalName: 'meals today example nonprofit, inc.' },
  { ein: FIXTURE_EINS.publicCharity, legalName: 'Springfield Animal Rescue' },
];

/** Your routing policy, not the SDK's. */
function routeNameOutcome(outcome) {
  switch (outcome) {
    case 'exact':
    case 'normalized':
      return 'continue — the submitted name agrees with an IRS-held name';
    case 'not_returned':
      return 'manual review — the API returned no name to compare against';
    default:
      return 'manual review — a human decides whether this is a rebrand, a typo, or the wrong EIN';
  }
}

for (const applicant of applicants) {
  const { nonprofit } = await client.nonprofits.check(applicant.ein);

  if (!nonprofit) {
    console.log(`No record for ${applicant.ein}.`);
    continue;
  }

  const comparison = compareName(applicant.legalName, {
    organization_name: nonprofit.organization_name,
    organization_name_aka: nonprofit.organization_name_aka,
  });

  heading(`Applicant: ${applicant.legalName}`);
  field('organization_name', nonprofit.organization_name);
  field('organization_name_aka', nonprofit.organization_name_aka);
  field('normalized applicant', comparison.submitted);

  for (const candidate of comparison.candidates) {
    bullet(`${candidate.source} normalizes to "${candidate.normalized}"`);
  }

  field('outcome', comparison.outcome);
  field('matched field', comparison.matchedField);
  field('agreement', isAgreement(comparison.outcome));
  field('routed to', routeNameOutcome(comparison.outcome));
}

note(
  'A name mismatch is a reason to look, not a finding. Organizations rebrand, file\n' +
    'under a parent, and appear in IRS data under a name no donor would recognize.\n' +
    'This example routes disagreement to review; it never labels an applicant.',
);
