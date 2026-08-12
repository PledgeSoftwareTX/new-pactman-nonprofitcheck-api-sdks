/**
 * EX-07 — Publication 78 and deductibility review.
 *
 * Publication 78 is the IRS list of organizations eligible to receive
 * tax-deductible charitable contributions, together with the limitation that
 * applies. A donation or grant workflow reads it to decide what to tell a donor
 * — and the deciding is the workflow's job, not the SDK's.
 *
 * Run:  PACTMAN_API_KEY=... node examples/ex-07-pub78-deductibility.mjs [EIN]
 */
import { getPub78 } from '@pactmandev/nonprofit-check-plus';
import { createClient } from './lib/client.mjs';
import { bullet, field, heading, note } from './lib/print.mjs';
import { FIXTURE_EINS } from './lib/fixture-api.mjs';
import { describeDeductibilityStatus } from './lib/irs-codes.mjs';

const client = createClient();
const ein = process.argv[2] ?? FIXTURE_EINS.publicCharity;

const { nonprofit } = await client.nonprofits.check(ein);

if (!nonprofit) {
  console.log(`No record for EIN ${ein}.`);
  process.exit(0);
}

const pub78 = getPub78(nonprofit);

if (pub78 === null) {
  console.log('The response carried no Publication 78 data for this organization.');
  process.exit(0);
}

heading('Publication 78 verification');
field('pub78_verified', pub78.verified);
field('pub78_organization_name', pub78.organization_name);
field('pub78_ein', pub78.ein);
field('pub78_city', pub78.city);
field('pub78_state', pub78.state);
field('pub78_indicator', pub78.indicator);
field('pub78_church_message', pub78.church_message);
field('most_recent_pub78', pub78.most_recent);

heading('Source organization types');
field('pub78_source_org_type_1', describeDeductibilityStatus(pub78.source_org_type_1).display);
field('pub78_source_org_type_2', describeDeductibilityStatus(pub78.source_org_type_2).display);
field('pub78_source_org_type_3', describeDeductibilityStatus(pub78.source_org_type_3).display);

heading('Deductibility entries');

if (!pub78.organization_types || pub78.organization_types.length === 0) {
  console.log('  No deductibility entries were returned.');
} else {
  for (const [index, entry] of pub78.organization_types.entries()) {
    const status = describeDeductibilityStatus(entry.deductibility_status_description);

    console.log(`  [${index}]`);
    field('  deductibility_status_description', status.display, 34);
    field('  deductibility_limitation', entry.deductibility_limitation, 34);
    field('  organization_type', entry.organization_type, 34);
  }
}

// Your policy, expressed against the source data. Change the predicate, not the
// SDK — nothing here is a verdict the API handed down.
heading('Applying a donation policy');

const policy = {
  requiresPub78Listing: true,
  acceptedDeductibilityLimitations: ['50%', '60%'],
};

const limitations = (pub78.organization_types ?? [])
  .map(entry => entry.deductibility_limitation)
  .filter(value => value !== null && value !== undefined);

const listed = pub78.verified === true;
const limitationAccepted = limitations.some(value =>
  policy.acceptedDeductibilityLimitations.includes(value),
);

bullet(`listed in Publication 78: ${listed}`);
bullet(`limitations returned: ${limitations.join(', ') || 'none'}`);
bullet(`limitation accepted by this policy: ${limitationAccepted}`);

field(
  'policy outcome',
  listed && limitationAccepted
    ? 'eligible under this application\'s own donation policy'
    : 'route to review — this application\'s policy is not satisfied by the returned data',
);

note(
  'The SDK maps Publication 78 data and stops there. Whether a classification\n' +
    'satisfies your donor communications, your grant agreement, or your tax\n' +
    'reporting obligations is a determination for your own counsel.',
);
