/**
 * EX-19 — Bulk partial success and item-level errors.
 *
 * A bulk request where some EINs matched and some did not is a success. It comes
 * back as HTTP 200 with organizations in `data` and the failures in `errors`.
 *
 * The successful records are fully usable. The failures keep the input EIN, so
 * you can reconcile every row of your input against an outcome instead of
 * discovering later that a grantee was silently skipped.
 *
 * Run:  PACTMAN_API_KEY=... node examples/ex-19-bulk-partial-success.mjs
 */
import { getAroe, getBmf, getPub78 } from '@pactmandev/nonprofit-check-plus';
import { FIXTURE_EINS, withFixtureApi } from './lib/fixture-api.mjs';
import { bullet, field, heading, note } from './lib/print.mjs';

await withFixtureApi(async client => {
  const submitted = [
    FIXTURE_EINS.publicCharity,
    FIXTURE_EINS.noRecord,
    FIXTURE_EINS.revoked,
    '123456789',
    FIXTURE_EINS.publicCharitySecond,
  ];

  const result = await client.nonprofits.checkBulk(submitted);

  heading('Mixed outcome');
  field('HTTP status', result.status);
  field('envelope code', result.raw.code);
  field('envelope message', result.raw.message);
  field('submitted', submitted.length);
  field('matched', result.organizations.length);
  field('item-level errors', result.errors.length);
  field('notFoundEins', result.notFoundEins.join(', '));

  // Successful records are ordinary records. Nothing about a sibling failure
  // degrades them.
  heading('Successful records remain fully usable');

  for (const org of result.organizations) {
    const bmf = getBmf(org);
    const pub78 = getPub78(org);
    const aroe = getAroe(org);

    console.log(`  ${org.ein}  ${org.organization_name}`);
    console.log(
      `    bmf_status=${bmf?.status}  pub78_verified=${pub78?.verified}` +
        `  revocation_date=${aroe?.revocation_date ?? '<null>'}`,
    );
  }

  heading('Failures, with their structured detail');

  for (const detail of result.errors) {
    bullet(`resource: ${detail.resource}`);
    bullet(`code: ${detail.code ?? '<none>'}`);
    bullet(`reason: ${detail.reason}`);
    bullet(`eins: ${JSON.stringify(detail.eins)}`);
  }

  // Reconcile every input against an outcome. This is the loop that keeps a
  // portfolio import honest.
  heading('Input reconciliation');

  const matched = new Map(result.organizations.map(org => [org.ein, org]));
  const missing = new Set(result.notFoundEins);
  const unaccounted = [];

  for (const [index, ein] of submitted.entries()) {
    let outcome;

    if (matched.has(ein)) {
      outcome = 'matched';
    } else if (missing.has(ein)) {
      outcome = 'no record — reported in errors';
    } else {
      outcome = 'UNACCOUNTED FOR — do not treat as checked';
      unaccounted.push(ein);
    }

    console.log(`  input[${index}] ${ein}  ${outcome}`);
  }

  field('\nunaccounted inputs', unaccounted.length);

  if (unaccounted.length > 0) {
    bullet('An input with no matching record and no error is not a pass. Re-check it.');
  }
});

note(
  'An EIN the API has no record for is a gap in the data, not a negative finding\n' +
    'about the organization. Route it to review; do not record it as "screened".',
);
