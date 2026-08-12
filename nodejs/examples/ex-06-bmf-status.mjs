/**
 * EX-06 — IRS Business Master File status inspection.
 *
 * Reads every BMF field the response carries: status, identity, subsection,
 * exemption, ruling and foundation classification.
 *
 * There is no `isExempt` here and none in the SDK. `bmf_status` is one source's
 * answer to one question; an organization can be listed in the BMF and still be
 * revoked, sanctioned, or in conflict with Publication 78.
 *
 * Run:  PACTMAN_API_KEY=... node examples/ex-06-bmf-status.mjs [EIN]
 */
import { getBmf } from '@pactmandev/nonprofit-check-plus';
import { createClient } from './lib/client.mjs';
import { field, heading, note } from './lib/print.mjs';
import { FIXTURE_EINS } from './lib/fixture-api.mjs';
import {
  describeExemptStatus,
  describeFilingRequirement,
  describePfFilingRequirement,
  formatRulingDate,
} from './lib/irs-codes.mjs';

const client = createClient();
const ein = process.argv[2] ?? FIXTURE_EINS.publicCharity;

const { nonprofit } = await client.nonprofits.check(ein);

if (!nonprofit) {
  console.log(`No record for EIN ${ein}.`);
  process.exit(0);
}

const bmf = getBmf(nonprofit);

if (bmf === null) {
  // Not "not in the BMF" — the API returned no BMF fields at all. Those are
  // different findings and this example refuses to merge them.
  console.log('The response carried no Business Master File data for this organization.');
  console.log('That is an absence of evidence, not a negative finding. Route it to review.');
  process.exit(0);
}

heading('BMF status');
field('bmf_status', bmf.status);
field('exempt_status_code', describeExemptStatus(bmf.exempt_status_code).display);
field('bmf_deductability_text', bmf.deductability_text);
field('most_recent_bmf', bmf.most_recent);

heading('BMF identity');
field('bmf_organization_name', bmf.organization_name);
field('bmf_ein', bmf.ein);
field('bmf_street_address', bmf.street_address);
field('bmf_city', bmf.city);
field('bmf_state', bmf.state);
field('bmf_church_message', bmf.church_message);

heading('Subsection');
field('bmf_subsection', bmf.subsection);
field('subsection_description', bmf.subsection_description);

heading('Exemption and ruling');
field('ruling date (year-month)', formatRulingDate(bmf.ruling_month, bmf.ruling_year));
field('ruling_month', bmf.ruling_month);
field('ruling_year', bmf.ruling_year);
field('group_exemption', bmf.group_exemption);

heading('Foundation classification');
field('foundation_code', bmf.foundation_code);
field('foundation_code_description', bmf.foundation_code_description);
field('foundation_type_code', bmf.foundation_type_code);
field('foundation_type_description', bmf.foundation_type_description);
field('foundation_509a_status', bmf.foundation_509a_status);

heading('Filing requirements');
field('filing_req_code', describeFilingRequirement(bmf.filing_req_code).display);
field('bmf_source_pf_filing_req_cd', describePfFilingRequirement(bmf.pf_filing_req_cd).display);

// Every value above came straight off the response. Turning them into an
// approve/decline decision is the next step, and it belongs in your policy code
// — see ex-26 for a worked routing example.
note(
  'The BMF is one of four sources this API reports. Reading it in isolation is how\n' +
    'a revoked or sanctioned organization passes a check: see ex-08 and ex-10.',
);
