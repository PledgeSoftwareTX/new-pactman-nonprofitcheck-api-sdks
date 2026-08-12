/**
 * EX-17 — Bulk screening of a grantee or nonprofit list.
 *
 * The shape of the work a grantmaker, DAF, employee-giving platform or migrating
 * consultant actually does: hand the API a list of EINs, walk the organizations
 * that came back, and keep the response-level metadata.
 *
 * One bulk request is one round trip and one rate-limit slot. Prefer it to a
 * loop of single checks.
 *
 * Run:  PACTMAN_API_KEY=... node examples/ex-17-bulk-screening.mjs
 */
import { MAX_BULK_EINS, getAroe, getBmf, getOfac, getPub78 } from '@pactmandev/nonprofit-check-plus';
import { FIXTURE_EINS, withFixtureApi } from './lib/fixture-api.mjs';
import { field, heading, note } from './lib/print.mjs';

/** A grantee portfolio as it might arrive from a spreadsheet import. */
const portfolio = [
  { ein: FIXTURE_EINS.publicCharity, grantee: 'Meals Today' },
  { ein: FIXTURE_EINS.publicCharitySecond, grantee: 'Aborjaily Fund' },
  { ein: FIXTURE_EINS.privateFoundation, grantee: 'Hartwell Family Foundation' },
  { ein: FIXTURE_EINS.revoked, grantee: 'Lapsed Filings Society' },
  { ein: FIXTURE_EINS.noRecord, grantee: 'Unknown Org From The Import' },
];

await withFixtureApi(async client => {
  const eins = portfolio.map(entry => entry.ein);

  heading(`Screening ${eins.length} EINs (server limit is ${MAX_BULK_EINS} per request)`);

  const result = await client.nonprofits.checkBulk(eins);

  // Response-level envelope fields, all reachable.
  field('status', result.status);
  field('raw.code', result.raw.code);
  field('raw.message', result.raw.message);
  field('timeTaken (ms)', result.timeTakenMs);
  field('nonprofit_check_count', result.checkCount);
  field('organizations returned', result.organizations.length);
  field('item-level errors', result.errors.length);
  field('notFoundEins', result.notFoundEins.join(', ') || '<none>');

  // Index by EIN. The response is a set of matched records, not a row-for-row
  // answer to your input list — see ex-18.
  const byEin = new Map(result.organizations.map(org => [org.ein, org]));

  heading('Organization-level results');

  for (const entry of portfolio) {
    const org = byEin.get(entry.ein);

    if (!org) {
      console.log(`  ${entry.ein}  ${entry.grantee.padEnd(28)} no record returned`);
      continue;
    }

    const bmf = getBmf(org);
    const pub78 = getPub78(org);
    const aroe = getAroe(org);
    const ofac = getOfac(org);

    console.log(
      `  ${org.ein}  ${String(org.organization_name).slice(0, 28).padEnd(28)}` +
        ` bmf=${bmf?.status}  pub78=${pub78?.verified}` +
        `  revoked=${Boolean(aroe?.revocation_date)}` +
        `  ofac=${ofac?.status ? (/UID:/.test(ofac.status) ? 'POSSIBLE MATCH' : 'no match') : 'unscreened'}` +
        `  conflict=${org.irs_bmf_pub78_conflict}`,
    );
  }

  heading('Item-level errors, verbatim');

  for (const detail of result.errors) {
    console.log(`  resource=${detail.resource}`);
    console.log(`  code=${detail.code ?? '<none>'}`);
    console.log(`  reason=${detail.reason}`);
    console.log(`  eins=${JSON.stringify(detail.eins)}`);
  }

  if (result.errors.length === 0) {
    console.log('  none');
  }
});

note(
  'This is a screening pass, not an approval pass. Each row above is source data\n' +
    'for your grant policy to act on — ex-27 shows one worked routing.',
);
