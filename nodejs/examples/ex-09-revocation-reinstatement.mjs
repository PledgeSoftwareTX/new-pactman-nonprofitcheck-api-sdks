/**
 * EX-09 — Revoked organization with reinstatement data.
 *
 * A record can carry both a revocation date and a reinstatement date. The two
 * stay separately accessible, because the gap between them matters: a donation
 * made while the exemption was revoked is not retroactively fixed by a later
 * reinstatement, and reinstatement can be retroactive or not.
 *
 * This example surfaces both dates and the interval, and still routes the record
 * to review. Reinstatement resolves one question, not every question.
 *
 * Run:  PACTMAN_API_KEY=... node examples/ex-09-revocation-reinstatement.mjs
 */
import { getAroe, getBmf, getPub78 } from '@pactmandev/nonprofit-check-plus';
import { FIXTURE_EINS, withFixtureApi } from './lib/fixture-api.mjs';
import { bullet, field, heading, note } from './lib/print.mjs';

/** The API formats dates as `M/DD/YYYY h:mm:ss AM`. Parse, never reformat in place. */
function parseApiDate(value) {
  if (!value) {
    return null;
  }

  const parsed = new Date(value);

  return Number.isNaN(parsed.getTime()) ? null : parsed;
}

function daysBetween(from, to) {
  return Math.round((to.getTime() - from.getTime()) / 86_400_000);
}

await withFixtureApi(async client => {
  const { nonprofit, requestId } = await client.nonprofits.check(FIXTURE_EINS.reinstated);

  if (!nonprofit) {
    console.log('No record returned.');
    return;
  }

  const aroe = getAroe(nonprofit);

  heading(`${nonprofit.organization_name} (${nonprofit.ein})`);

  // Both dates are their own field. Nothing collapses them into a single
  // "currently revoked" boolean, because that boolean would lose the interval.
  field('revocation_code', aroe?.revocation_code);
  field('revocation_date', aroe?.revocation_date);
  field('reinstatement_date', aroe?.reinstatement_date);
  field('aroe_list_published_date', aroe?.list_published_date);

  const revokedAt = parseApiDate(aroe?.revocation_date);
  const reinstatedAt = parseApiDate(aroe?.reinstatement_date);

  heading('Derived, in application code');

  if (revokedAt && reinstatedAt) {
    bullet(`revoked on ${revokedAt.toISOString().slice(0, 10)}`);
    bullet(`reinstated on ${reinstatedAt.toISOString().slice(0, 10)}`);
    bullet(`exemption lapsed for ${daysBetween(revokedAt, reinstatedAt)} days`);
    bullet('donations dated inside that window may need separate handling');
  } else if (revokedAt) {
    bullet('revoked, with no reinstatement date returned');
  } else {
    bullet('no revocation history returned');
  }

  heading('What the other sources say now');
  field('bmf_status', getBmf(nonprofit)?.status);
  field('pub78_verified', getPub78(nonprofit)?.verified);
  field('irs_bmf_pub78_conflict', nonprofit.irs_bmf_pub78_conflict);

  heading('Outcome');

  const questionsReinstatementDoesNotAnswer = [
    'Was the reinstatement retroactive to the revocation date?',
    'Do gifts made during the lapse need to be re-characterized?',
    'Does your grant agreement require continuous exemption?',
    'Has the organization filed since reinstatement?',
  ];

  for (const question of questionsReinstatementDoesNotAnswer) {
    bullet(question);
  }

  field(
    '\npolicy action',
    'manual review — reinstatement is recorded, and the record still has history',
  );

  console.log('\n  evidence retained:');
  console.log(
    JSON.stringify(
      {
        ein: nonprofit.ein,
        requestId,
        checkedAt: new Date().toISOString(),
        revocation_date: nonprofit.revocation_date,
        reinstatement_date: nonprofit.reinstatement_date,
        revocation_code: nonprofit.revocation_code,
        aroe_list_published_date: nonprofit.aroe_list_published_date,
      },
      null,
      2,
    )
      .split('\n')
      .map(line => `    ${line}`)
      .join('\n'),
  );
});

note(
  'The API answers "what does the IRS revocation data show". It does not answer\n' +
    '"is this organization eligible today" — that needs your policy, and often your\n' +
    'counsel.',
);
