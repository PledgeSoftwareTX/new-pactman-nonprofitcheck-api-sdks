/**
 * EX-29 — Pre-payment or pre-disbursement recheck.
 *
 * An organization approved at onboarding is not an organization approved today.
 * Exemptions get revoked, sanctions lists get republished, and IRS data lands on
 * its own schedule — all of it after your approval and before your payout.
 *
 * This example rechecks immediately before the money moves, compares the fresh
 * findings with the stored ones, and pauses the workflow on a material change.
 * Both sets of evidence are kept: the payout is defensible only if you can show
 * what you knew, and when.
 *
 * Run:  PACTMAN_API_KEY=... node examples/ex-29-pre-disbursement-recheck.mjs
 */
import { FIXTURE_EINS, withFixtureApi } from './lib/fixture-api.mjs';
import { bullet, field, heading, note, render } from './lib/print.mjs';
import { collectFindings, concerns, diffFindings } from './lib/screening.mjs';

/** Changes that stop a disbursement outright at this organization. */
const BLOCKING_CHANGES = new Set([
  'revocation_code',
  'revocation_date',
  'ofac_state',
  'bmf_status',
  'pub78_verified',
  'irs_bmf_pub78_conflict',
]);

/**
 * Verification evidence stored when each payee was approved.
 *
 * Store the findings, not a verdict: "approved" alone cannot be re-examined.
 */
const storedVerifications = new Map([
  [
    FIXTURE_EINS.publicCharity,
    {
      approvedAt: '2026-02-11T14:05:00.000Z',
      requestId: 'req-onboarding-8841',
      findings: {
        organization_name: 'MEALS TODAY EXAMPLE NONPROFIT',
        bmf_status: true,
        exempt_status_code: '01',
        pub78_verified: true,
        revocation_code: null,
        revocation_date: null,
        reinstatement_date: null,
        ofac_state: 'no_match',
        irs_bmf_pub78_conflict: false,
        foundation_type_code: 'pc',
        subsection_description: '501(c)(3) Public Charity',
      },
    },
  ],
  [
    // Approved while in good standing. The IRS data now says otherwise.
    FIXTURE_EINS.revoked,
    {
      approvedAt: '2026-01-06T10:22:00.000Z',
      requestId: 'req-onboarding-7310',
      findings: {
        organization_name: 'LAPSED FILINGS EXAMPLE SOCIETY',
        bmf_status: true,
        exempt_status_code: '01',
        pub78_verified: true,
        revocation_code: null,
        revocation_date: null,
        reinstatement_date: null,
        ofac_state: 'no_match',
        irs_bmf_pub78_conflict: false,
        foundation_type_code: 'pc',
        subsection_description: '501(c)(3) Public Charity',
      },
    },
  ],
]);

const pendingDisbursements = [
  { paymentId: 'PAY-5501', ein: FIXTURE_EINS.publicCharity, amount: 12_400 },
  { paymentId: 'PAY-5502', ein: FIXTURE_EINS.revoked, amount: 3_150 },
];

await withFixtureApi(async client => {
  const releases = [];

  for (const payment of pendingDisbursements) {
    heading(`${payment.paymentId} — $${payment.amount.toLocaleString()} to ${payment.ein}`);

    const stored = storedVerifications.get(payment.ein);
    let result;

    try {
      // Retries stay on: a transient failure here should be absorbed, not turned
      // into a false "changed" signal.
      result = await client.nonprofits.check(payment.ein, { timeoutMs: 10_000 });
    } catch (error) {
      // Could not verify. That is a hold, never a release — an unreachable API
      // is not evidence that anything is fine.
      field('recheck', `failed: ${error.constructor.name}`);
      field('decision', 'HOLD — the payee could not be re-verified before payout');
      releases.push({ ...payment, decision: 'hold', reason: 'recheck_failed' });
      continue;
    }

    if (!result.nonprofit) {
      field('recheck', 'no record returned');
      field('decision', 'HOLD — the payee no longer returns a record');
      releases.push({ ...payment, decision: 'hold', reason: 'no_record' });
      continue;
    }

    const current = collectFindings(result.nonprofit);
    const changes = diffFindings(stored?.findings, current);
    const blocking = changes.filter(change => BLOCKING_CHANGES.has(change.field));
    const issues = concerns(current, { staleAfterDays: 120 });

    field('approved at', stored?.approvedAt);
    field('rechecked at', new Date().toISOString());
    field('fields changed since approval', changes.length);

    for (const change of changes) {
      bullet(
        `${change.field}: ${render(change.before)} → ${render(change.after)}` +
          `${BLOCKING_CHANGES.has(change.field) ? '   [blocking]' : ''}`,
      );
    }

    if (changes.length === 0) {
      bullet('no material field changed');
    }

    for (const issue of issues) {
      bullet(`current concern: ${issue}`);
    }

    const decision = blocking.length > 0 || issues.length > 0 ? 'hold' : 'release';

    field(
      'decision',
      decision === 'release'
        ? 'RELEASE — findings are unchanged and no concern is open'
        : 'HOLD — a material change or open concern was found before payout',
    );

    // Both snapshots are kept. Neither overwrites the other.
    releases.push({
      ...payment,
      decision,
      priorVerification: stored,
      currentVerification: {
        checkedAt: new Date().toISOString(),
        requestId: result.requestId,
        reportDate: result.nonprofit.report_date,
        findings: current,
      },
      changes,
      blockingChanges: blocking.map(change => change.field),
    });
  }

  heading('Payment run');

  for (const release of releases) {
    console.log(
      `  ${release.paymentId}  ${release.ein}  ${release.decision.toUpperCase().padEnd(8)}` +
        ` ${release.blockingChanges?.length ? `blocked by: ${release.blockingChanges.join(', ')}` : ''}`,
    );
  }

  const held = releases.filter(release => release.decision === 'hold');

  field('\nreleased', releases.length - held.length);
  field('held for review', held.length);
  bullet('Each held payment retains the prior and the current verification evidence.');
});

note(
  'Recheck as close to the money movement as your workflow allows. A check from\n' +
    'onboarding proves what was true at onboarding, and a payout is a decision made\n' +
    'today.',
);
