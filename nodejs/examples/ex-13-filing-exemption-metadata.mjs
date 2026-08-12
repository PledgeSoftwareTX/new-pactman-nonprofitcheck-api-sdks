/**
 * EX-13 — Filing and exemption metadata.
 *
 * Displays `filing_req_code`, the exemption status, the ruling date and the
 * other IRS classification codes on the response.
 *
 * Two rules apply to every code below:
 *
 *   - the raw value is preserved exactly as the API sent it, `null` included
 *   - a code is only labelled through a documented table with an unknown-value
 *     fallback, so a value added by the IRS reads as "unrecognized", never as
 *     `undefined` and never as the wrong label
 *
 * Run:  PACTMAN_API_KEY=... node examples/ex-13-filing-exemption-metadata.mjs
 */
import { getBmf } from '@pactmandev/nonprofit-check-plus';
import { FIXTURE_EINS, withFixtureApi } from './lib/fixture-api.mjs';
import { field, heading, note, render } from './lib/print.mjs';
import {
  describeExemptStatus,
  describeFilingRequirement,
  describePfFilingRequirement,
  formatRulingDate,
} from './lib/irs-codes.mjs';

function codeRow(label, mapped) {
  console.log(
    `  ${label.padEnd(28)} raw=${render(mapped.code).padEnd(10)}` +
      ` known=${String(mapped.known).padEnd(6)} ${mapped.description ?? mapped.display}`,
  );
}

await withFixtureApi(async client => {
  const cases = [
    ['public charity', FIXTURE_EINS.publicCharity],
    ['private foundation', FIXTURE_EINS.privateFoundation],
    ['revoked — status code differs', FIXTURE_EINS.revoked],
    ['sparse — several codes are null', FIXTURE_EINS.sparseIdentity],
  ];

  for (const [label, ein] of cases) {
    const { nonprofit } = await client.nonprofits.check(ein);

    if (!nonprofit) {
      console.log(`No record for ${ein}.`);
      continue;
    }

    const bmf = getBmf(nonprofit);

    heading(`${label} — ${nonprofit.organization_name}`);

    codeRow('filing_req_code', describeFilingRequirement(bmf?.filing_req_code));
    codeRow('bmf_source_pf_filing_req_cd', describePfFilingRequirement(bmf?.pf_filing_req_cd));
    codeRow('exempt_status_code', describeExemptStatus(bmf?.exempt_status_code));

    // Codes the API already describes for you. Read the description it sends;
    // do not shadow it with a local table that will drift.
    field('bmf_subsection', bmf?.subsection);
    field('subsection_description', bmf?.subsection_description);
    field('foundation_code', bmf?.foundation_code);
    field('foundation_code_description', bmf?.foundation_code_description);

    field('ruling_month', bmf?.ruling_month);
    field('ruling_year', bmf?.ruling_year);
    field('ruling date', formatRulingDate(bmf?.ruling_month, bmf?.ruling_year));
    field('group_exemption', bmf?.group_exemption);
    field('revocation_code', nonprofit.revocation_code);
  }

  // An unknown code must survive the round trip intact. This is the case that
  // breaks applications which map codes eagerly into an enum.
  const { nonprofit } = await client.nonprofits.check(FIXTURE_EINS.futureFields);

  heading('A code this SDK version has never seen');
  field('foundation_type_code', nonprofit?.foundation_type_code);
  field('foundation_type_description', nonprofit?.foundation_type_description);
  codeRow('exempt_status_code (forced)', describeExemptStatus('99'));
  field('value preserved', nonprofit?.foundation_type_code === 'zz');
});

note(
  'Never coerce an unrecognized code to a default. "Unknown" is a real state and\n' +
    'usually means review, not approval — see ex-25 for the same rule applied to\n' +
    'whole fields the SDK does not know about yet.',
);
