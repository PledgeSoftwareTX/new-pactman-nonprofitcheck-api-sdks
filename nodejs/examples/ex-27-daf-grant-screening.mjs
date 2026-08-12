/**
 * EX-27 — DAF grant-recommendation screening.
 *
 * A donor recommends a grant. Before the recommendation advances, the sponsoring
 * organization screens the grantee, shows the tax and foundation classification
 * to the grants team, and sends anything revoked, sanctioned, conflicting or
 * ambiguous to review.
 *
 * A DAF's rules are stricter than a donation platform's — compare the policy
 * block here with the one in ex-26. Same API data, different obligations,
 * different outcomes. That difference is precisely why the SDK does not decide.
 *
 * Run:  PACTMAN_API_KEY=... node examples/ex-27-daf-grant-screening.mjs
 */
import { FIXTURE_EINS, withFixtureApi } from './lib/fixture-api.mjs';
import { bullet, field, heading, note } from './lib/print.mjs';
import { collectFindings, concerns } from './lib/screening.mjs';

/** This sponsoring organization's rules. Yours will differ. */
const POLICY = {
  staleAfterDays: 90,
  // A private foundation grantee is not refused — it takes a different path,
  // because expenditure responsibility applies.
  privateFoundationRequiresExpenditureResponsibility: true,
  // Anything the screen could not establish stops the recommendation.
  treatUnknownAsBlocking: true,
};

const recommendations = [
  { grantId: 'G-1001', ein: FIXTURE_EINS.publicCharity, amount: 25_000, donor: 'Fund 88' },
  { grantId: 'G-1002', ein: FIXTURE_EINS.privateFoundation, amount: 10_000, donor: 'Fund 88' },
  { grantId: 'G-1003', ein: FIXTURE_EINS.revoked, amount: 5_000, donor: 'Fund 14' },
  { grantId: 'G-1004', ein: FIXTURE_EINS.ofacMatch, amount: 40_000, donor: 'Fund 14' },
  { grantId: 'G-1005', ein: FIXTURE_EINS.conflicted, amount: 7_500, donor: 'Fund 03' },
  { grantId: 'G-1006', ein: FIXTURE_EINS.reinstated, amount: 15_000, donor: 'Fund 03' },
  { grantId: 'G-1007', ein: FIXTURE_EINS.sparseIdentity, amount: 2_000, donor: 'Fund 21' },
];

function screen(findings) {
  const issues = concerns(findings, { staleAfterDays: POLICY.staleAfterDays });

  if (findings.ofac_state === 'match') {
    return { outcome: 'blocked', queue: 'sanctions_review', issues };
  }

  if (findings.revoked && !findings.reinstated) {
    return { outcome: 'blocked', queue: 'tax_status_review', issues };
  }

  if (findings.irs_bmf_pub78_conflict === true) {
    return { outcome: 'held', queue: 'source_conflict_review', issues };
  }

  if (POLICY.treatUnknownAsBlocking && issues.length > 0) {
    return { outcome: 'held', queue: 'grants_review', issues };
  }

  const isPrivateFoundation = findings.foundation_type_code === 'pf';

  if (isPrivateFoundation && POLICY.privateFoundationRequiresExpenditureResponsibility) {
    return { outcome: 'held', queue: 'expenditure_responsibility', issues };
  }

  return { outcome: 'advanced', queue: 'ready_for_approval', issues };
}

await withFixtureApi(async client => {
  // One bulk call for the whole recommendation batch.
  const result = await client.nonprofits.checkBulk(recommendations.map(entry => entry.ein));
  const byEin = new Map(result.organizations.map(org => [org.ein, org]));

  heading('Screening batch');
  field('recommendations', recommendations.length);
  field('records returned', result.organizations.length);
  field('no record for', result.notFoundEins.join(', ') || '<none>');
  field('checks used this cycle', result.checkCount);

  const decisions = [];

  for (const recommendation of recommendations) {
    const nonprofit = byEin.get(recommendation.ein);

    heading(`${recommendation.grantId} — $${recommendation.amount.toLocaleString()} to ${recommendation.ein}`);

    if (!nonprofit) {
      field('outcome', 'held');
      field('queue', 'grants_review');
      bullet('No record was returned for this EIN. Nothing was verified.');
      decisions.push({ ...recommendation, outcome: 'held', queue: 'grants_review' });
      continue;
    }

    const findings = collectFindings(nonprofit);
    const screened = screen(findings);

    // What the grants team sees on screen.
    field('grantee', findings.organization_name);
    field('also known as', findings.organization_name_aka);
    field('subsection', findings.subsection_description);
    field('foundation type', findings.foundation_type_description);
    field('foundation type code', findings.foundation_type_code);
    field('deductibility limitations', findings.deductibility_limitations.join(', ') || '<none>');
    field('bmf_status', findings.bmf_status);
    field('pub78_verified', findings.pub78_verified);
    field('revocation_date', findings.revocation_date);
    field('reinstatement_date', findings.reinstatement_date);
    field('ofac state', findings.ofac_state);
    field('conflict flag', findings.irs_bmf_pub78_conflict);
    field('oldest source (days)', findings.oldest_source_age_days);

    field('outcome', screened.outcome);
    field('queue', screened.queue);

    for (const issue of screened.issues) {
      bullet(issue);
    }

    decisions.push({
      ...recommendation,
      outcome: screened.outcome,
      queue: screened.queue,
      screenedAt: new Date().toISOString(),
      requestId: result.requestId,
      sourceFindings: findings,
    });
  }

  heading('Recommendation queue');

  for (const decision of decisions) {
    console.log(
      `  ${decision.grantId}  ${decision.ein}  ${decision.outcome.padEnd(9)} → ${decision.queue}`,
    );
  }

  const advanced = decisions.filter(decision => decision.outcome === 'advanced');

  field('\nadvanced to approval', advanced.length);
  field('held or blocked', decisions.length - advanced.length);
});

note(
  'Advancing a recommendation is a step in this DAF\'s process, not a legal approval\n' +
    'of the grant. The findings recorded above are the source data the decision\n' +
    'rested on; the determination itself remains the sponsoring organization\'s.',
);
