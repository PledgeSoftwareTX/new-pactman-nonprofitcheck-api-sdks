/**
 * EX-03 — Basic nonprofit identity lookup.
 *
 * Retrieves an organization and reads its identity fields. The typed model and
 * the untouched response body are both available; neither replaces the other.
 *
 * Run:  PACTMAN_API_KEY=... node examples/ex-03-identity-lookup.mjs [EIN]
 */
import { createClient } from './lib/client.mjs';
import { field, heading, note } from './lib/print.mjs';
import { FIXTURE_EINS } from './lib/fixture-api.mjs';

const client = createClient();
const ein = process.argv[2] ?? FIXTURE_EINS.publicCharity;

const result = await client.nonprofits.check(ein);

if (!result.nonprofit) {
  console.log(`No record for EIN ${ein}.`);
  process.exit(0);
}

const { nonprofit } = result;

heading('Identity');
field('ein', nonprofit.ein);
field('organization_name', nonprofit.organization_name);
field('organization_name_aka', nonprofit.organization_name_aka);
field('pactman_org_url', nonprofit.pactman_org_url);

// `organization_name_aka` is frequently null. That is "the API has no alternate
// name on file", not "the organization has no alternate name".

heading('Response metadata');
field('status', result.status);
field('requestId', result.requestId);
field('timeTakenMs', result.timeTakenMs);
field('checkCount', result.checkCount);

// The structured model is a view over the envelope, not a replacement for it.
// `raw` is exactly what the server sent, including anything not typed above.
heading('Raw envelope');
field('raw.code', result.raw.code);
field('raw.message', result.raw.message);
field('raw.data.ein', result.raw.data?.ein);
field('fields returned', Object.keys(nonprofit).length);

note(
  'A returned profile URL means Pactman holds a page for the organization. It is\n' +
    'not an endorsement, and not a statement about tax-exempt status.',
);
