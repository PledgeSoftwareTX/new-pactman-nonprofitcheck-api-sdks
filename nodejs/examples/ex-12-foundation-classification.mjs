/**
 * EX-12 — Organization type and foundation classification.
 *
 * A grantmaker or DAF needs the classification on screen: public charity or
 * private foundation, which 509(a) paragraph, which deductibility limitation.
 * The SDK maps every one of those fields and declares none of them grant-eligible.
 *
 * Note which values are read from the API's own `*_description` fields rather
 * than a local table. Descriptions the source supplies stay correct when the
 * source changes; a lookup table in your repository does not.
 *
 * Run:  PACTMAN_API_KEY=... node examples/ex-12-foundation-classification.mjs
 */
import { getBmf, getPub78 } from '@pactmandev/nonprofit-check-plus';
import { FIXTURE_EINS, withFixtureApi } from './lib/fixture-api.mjs';
import { field, heading, note } from './lib/print.mjs';
import { describeDeductibilityStatus, describePfFilingRequirement } from './lib/irs-codes.mjs';

/** What a grant officer sees. Every value is copied, none is computed. */
function classificationPanel(nonprofit) {
  const bmf = getBmf(nonprofit);
  const pub78 = getPub78(nonprofit);

  return {
    'subsection code': bmf?.subsection,
    'subsection description': bmf?.subsection_description,
    'foundation code': bmf?.foundation_code,
    'foundation code description': bmf?.foundation_code_description,
    'foundation type code': bmf?.foundation_type_code,
    'foundation type description': bmf?.foundation_type_description,
    '509(a) status': bmf?.foundation_509a_status,
    'deductibility text': bmf?.deductability_text,
    '990-PF filing requirement': describePfFilingRequirement(bmf?.pf_filing_req_cd).display,
    'Pub 78 org type 1': describeDeductibilityStatus(pub78?.source_org_type_1).display,
  };
}

await withFixtureApi(async client => {
  for (const ein of [FIXTURE_EINS.publicCharity, FIXTURE_EINS.privateFoundation]) {
    const { nonprofit } = await client.nonprofits.check(ein);

    if (!nonprofit) {
      console.log(`No record for ${ein}.`);
      continue;
    }

    heading(`${nonprofit.organization_name} (${nonprofit.ein})`);

    for (const [label, value] of Object.entries(classificationPanel(nonprofit))) {
      field(label, value);
    }

    heading('  organization_types');

    const types = getPub78(nonprofit)?.organization_types;

    if (!types || types.length === 0) {
      console.log('    none returned');
    } else {
      for (const [index, entry] of types.entries()) {
        console.log(`    [${index}] status=${entry.deductibility_status_description}` +
          ` limitation=${entry.deductibility_limitation}`);
      }
    }

    // A DAF's own rules live here, and they are visibly the DAF's. A private
    // foundation grantee is not disqualified — it is routed differently, because
    // expenditure responsibility and the deductibility limit both change.
    const isPrivateFoundation =
      getBmf(nonprofit)?.foundation_type_code === 'pf' || getBmf(nonprofit)?.pf_filing_req_cd === '1';

    field(
      '\nthis application routes to',
      isPrivateFoundation
        ? 'private-foundation workflow — expenditure responsibility review'
        : 'standard public-charity workflow',
    );
  }
});

note(
  'Displaying a classification is not asserting grant eligibility. The SDK reports\n' +
    'the IRS classification; whether a grant may be made, and on what terms, is your\n' +
    'grantmaking policy and your counsel\'s call.',
);
