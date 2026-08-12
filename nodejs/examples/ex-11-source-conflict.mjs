/**
 * EX-11 — Cross-source conflict or inconsistency.
 *
 * `irs_bmf_pub78_conflict` is true when the Business Master File and Publication
 * 78 disagree about an organization. The API reports the disagreement instead of
 * resolving it, and so does this example: it records what each source said and
 * creates a review outcome.
 *
 * Silently preferring one source is the failure mode here. Whichever you pick,
 * you will be wrong for some organization, and you will have destroyed the
 * evidence that would have shown it.
 *
 * Run:  PACTMAN_API_KEY=... node examples/ex-11-source-conflict.mjs
 */
import { getAroe, getBmf, getOfac, getPub78 } from '@pactmandev/nonprofit-check-plus';
import { FIXTURE_EINS, withFixtureApi } from './lib/fixture-api.mjs';
import { bullet, field, heading, note, render } from './lib/print.mjs';
import { normalizeName } from './lib/matching.mjs';

/** Case and punctuation differences are not disagreements. See ex-04. */
const loosely = value => String(value).toUpperCase().trim();

/** Fields the two IRS sources both report, so disagreement is visible per pair. */
const CROSS_SOURCE_PAIRS = [
  {
    label: 'organization name',
    bmf: 'organization_name',
    pub78: 'organization_name',
    normalize: normalizeName,
  },
  { label: 'EIN', bmf: 'ein', pub78: 'ein', normalize: loosely },
  { label: 'city', bmf: 'city', pub78: 'city', normalize: loosely },
  { label: 'state', bmf: 'state', pub78: 'state', normalize: loosely },
];

function collectConflicts(nonprofit) {
  const bmf = getBmf(nonprofit);
  const pub78 = getPub78(nonprofit);
  const findings = [];

  // The flag the API sets. This is the authoritative signal; the per-field
  // comparison below only explains it.
  if (nonprofit.irs_bmf_pub78_conflict === true) {
    findings.push({
      field: 'irs_bmf_pub78_conflict',
      detail: 'The API flagged a BMF / Publication 78 disagreement.',
    });
  }

  if (bmf?.status === true && pub78?.verified === false) {
    findings.push({
      field: 'bmf_status vs pub78_verified',
      detail: 'The BMF lists the organization as exempt; Publication 78 does not list it.',
    });
  }

  if (bmf?.status === false && pub78?.verified === true) {
    findings.push({
      field: 'bmf_status vs pub78_verified',
      detail: 'Publication 78 lists the organization; the BMF does not show it as exempt.',
    });
  }

  for (const pair of CROSS_SOURCE_PAIRS) {
    const bmfValue = bmf?.[pair.bmf];
    const pub78Value = pub78?.[pair.pub78];

    // Only compare when both sources actually supplied a value. A field one
    // source omitted is missing data, not a conflict.
    if (bmfValue == null || pub78Value == null) {
      continue;
    }

    if (pair.normalize(bmfValue) !== pair.normalize(pub78Value)) {
      findings.push({
        field: pair.label,
        detail: `BMF "${bmfValue}" vs Publication 78 "${pub78Value}"`,
      });
    }
  }

  return findings;
}

await withFixtureApi(async client => {
  for (const ein of [FIXTURE_EINS.conflicted, FIXTURE_EINS.publicCharity]) {
    const result = await client.nonprofits.check(ein);
    const { nonprofit } = result;

    if (!nonprofit) {
      console.log(`No record for ${ein}.`);
      continue;
    }

    const conflicts = collectConflicts(nonprofit);

    heading(`${nonprofit.organization_name} (${nonprofit.ein})`);
    field('irs_bmf_pub78_conflict', nonprofit.irs_bmf_pub78_conflict);
    field('conflicting signals', conflicts.length);

    for (const conflict of conflicts) {
      bullet(`${conflict.field}: ${conflict.detail}`);
    }

    if (conflicts.length === 0) {
      bullet('sources agree on every field both of them returned');
    }

    // Nothing is chosen. Both sides are kept, side by side, for the reviewer.
    const bmf = getBmf(nonprofit);
    const pub78 = getPub78(nonprofit);

    console.log('\n  source-by-source view:');
    console.log(`    ${'field'.padEnd(20)} ${'BMF'.padEnd(30)} Publication 78`);

    for (const pair of CROSS_SOURCE_PAIRS) {
      console.log(
        `    ${pair.label.padEnd(20)} ${render(bmf?.[pair.bmf]).padEnd(30)} ${render(pub78?.[pair.pub78])}`,
      );
    }

    console.log(
      `    ${'exempt/listed'.padEnd(20)} ${render(bmf?.status).padEnd(30)} ${render(pub78?.verified)}`,
    );

    const outcome = conflicts.length > 0 ? 'manual_review' : 'continue';

    field('\npolicy outcome', outcome);

    if (outcome === 'manual_review') {
      const reviewRecord = {
        ein: nonprofit.ein,
        requestId: result.requestId,
        checkedAt: new Date().toISOString(),
        reportDate: nonprofit.report_date,
        conflicts,
        sources: {
          bmf,
          pub78,
          aroe: getAroe(nonprofit),
          ofac: getOfac(nonprofit),
        },
      };

      console.log(`    review record: ${JSON.stringify(reviewRecord).length} bytes retained`);
      console.log(`    conflicting fields: ${conflicts.map(item => item.field).join(', ')}`);
    }
  }
});

note(
  'A conflict is a fact about the data, not a fact about the organization. Record\n' +
    'both sources, escalate, and let a person decide which one governs your workflow.',
);
