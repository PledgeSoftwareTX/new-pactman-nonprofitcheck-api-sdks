/**
 * EX-08 — Automatic revocation detected.
 *
 * An organization that fails to file for three consecutive years has its
 * exemption revoked automatically and appears in the IRS Automatic Revocation of
 * Exemption (AROE) data. The API reports that with `revocation_code` and
 * `revocation_date`.
 *
 * This example flags the record and preserves the source fields verbatim. It
 * does not decide the outcome — blocking, holding, or reviewing is your policy.
 *
 * Run:  PACTMAN_API_KEY=... node examples/ex-08-automatic-revocation.mjs
 */
import { getAroe, getBmf, getPub78 } from '@pactmandev/nonprofit-check-plus';
import { FIXTURE_EINS, withFixtureApi } from './lib/fixture-api.mjs';
import { field, heading, note } from './lib/print.mjs';

/** The application's policy, in one place, expressed against source fields. */
const POLICY = {
  onRevokedWithoutReinstatement: 'block',
  onRevokedWithReinstatement: 'manual_review',
  onNoRevocationData: 'continue',
};

function assessRevocation(nonprofit) {
  const aroe = getAroe(nonprofit);

  if (aroe === null) {
    return { action: POLICY.onNoRevocationData, reason: 'No revocation fields were returned.', aroe };
  }

  const revoked = Boolean(aroe.revocation_code || aroe.revocation_date);

  if (!revoked) {
    return {
      action: POLICY.onNoRevocationData,
      reason: 'Revocation fields were returned and are empty.',
      aroe,
    };
  }

  return aroe.reinstatement_date
    ? {
        action: POLICY.onRevokedWithReinstatement,
        reason: 'Revoked, with a reinstatement date present — see ex-09.',
        aroe,
      }
    : {
        action: POLICY.onRevokedWithoutReinstatement,
        reason: 'Appears in the Automatic Revocation data with no reinstatement.',
        aroe,
      };
}

await withFixtureApi(async client => {
  for (const ein of [FIXTURE_EINS.revoked, FIXTURE_EINS.publicCharity]) {
    const result = await client.nonprofits.check(ein);
    const { nonprofit } = result;

    if (!nonprofit) {
      console.log(`No record for ${ein}.`);
      continue;
    }

    const assessment = assessRevocation(nonprofit);

    heading(`${nonprofit.organization_name} (${nonprofit.ein})`);
    field('revocation_code', assessment.aroe?.revocation_code);
    field('revocation_date', assessment.aroe?.revocation_date);
    field('reinstatement_date', assessment.aroe?.reinstatement_date);
    field('aroe_list_published_date', assessment.aroe?.list_published_date);

    // Revocation shows up in the other sources too. Capture what each one said,
    // rather than letting one field speak for all of them.
    field('bmf_status', getBmf(nonprofit)?.status);
    field('pub78_verified', getPub78(nonprofit)?.verified);
    field('exempt_status_code', getBmf(nonprofit)?.exempt_status_code);

    field('policy action', assessment.action);
    field('reason', assessment.reason);

    // What you keep is what you can explain later. Store the source fields, the
    // request identifier, and the time you looked — not just the verdict.
    const auditRecord = {
      ein: nonprofit.ein,
      checkedAt: new Date().toISOString(),
      requestId: result.requestId,
      action: assessment.action,
      sourceFindings: {
        revocation_code: nonprofit.revocation_code,
        revocation_date: nonprofit.revocation_date,
        reinstatement_date: nonprofit.reinstatement_date,
        aroe_list_published_date: nonprofit.aroe_list_published_date,
        bmf_status: nonprofit.bmf_status,
        pub78_verified: nonprofit.pub78_verified,
      },
    };

    console.log('\n  audit record:');
    console.log(
      JSON.stringify(auditRecord, null, 2)
        .split('\n')
        .map(line => `    ${line}`)
        .join('\n'),
    );
  }
});

note(
  'The SDK reports what the AROE data says. It does not decide whether a revoked\n' +
    'organization may receive a donation, a grant, or a payout — that is a legal and\n' +
    'compliance determination your application owns.',
);
