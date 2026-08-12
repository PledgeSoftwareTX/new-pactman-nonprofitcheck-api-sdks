/**
 * EX-30 — Scheduled portfolio re-verification and audit trail.
 *
 * A platform or consultant rechecks every onboarded organization on its own
 * schedule, records what changed in status, revocation, reinstatement, OFAC,
 * identity, classification and data freshness, and writes an audit entry it can
 * still explain a year later.
 *
 * What makes an audit trail useful is not the outcome — it is the evidence next
 * to the outcome: when the check ran, which request it was, what each source
 * said, which policy version applied, and what changed since last time.
 *
 * Run:  PACTMAN_API_KEY=... node examples/ex-30-portfolio-reverification.mjs
 */
import { MAX_BULK_EINS } from '@pactmandev/nonprofit-check-plus';
import { FIXTURE_EINS, withFixtureApi } from './lib/fixture-api.mjs';
import { bullet, field, heading, note, render } from './lib/print.mjs';
import { MATERIAL_FIELDS, collectFindings, concerns, diffFindings } from './lib/screening.mjs';

/** Identify the rules that produced an outcome, so old entries stay readable. */
const POLICY_VERSION = '2026.02-portfolio-rev3';
const RE_REVIEW_INTERVAL_DAYS = 90;

/** The portfolio, with whatever the last run stored. */
const portfolio = [
  { ein: FIXTURE_EINS.publicCharity, onboardedAt: '2025-11-02', lastFindings: null },
  { ein: FIXTURE_EINS.publicCharitySecond, onboardedAt: '2025-12-14', lastFindings: null },
  { ein: FIXTURE_EINS.privateFoundation, onboardedAt: '2026-01-09', lastFindings: null },
  {
    ein: FIXTURE_EINS.reinstated,
    onboardedAt: '2025-09-30',
    // Stored at the previous run, before the reinstatement was published.
    lastFindings: {
      organization_name: 'SECOND CHANCE EXAMPLE ALLIANCE',
      bmf_status: true,
      exempt_status_code: '01',
      pub78_verified: true,
      revocation_code: '01',
      revocation_date: '2/06/2022 9:41:03 PM',
      reinstatement_date: null,
      ofac_state: 'no_match',
      irs_bmf_pub78_conflict: false,
      foundation_type_code: 'pc',
      subsection_description: '501(c)(3) Public Charity',
    },
  },
  { ein: FIXTURE_EINS.ofacMatch, onboardedAt: '2026-02-01', lastFindings: null },
  { ein: FIXTURE_EINS.noRecord, onboardedAt: '2025-08-21', lastFindings: null },
];

/** Splits the portfolio into requests the server will accept. */
function batch(eins, size = MAX_BULK_EINS) {
  const batches = [];

  for (let index = 0; index < eins.length; index += size) {
    batches.push(eins.slice(index, index + size));
  }

  return batches;
}

function outcomeFor(findings, changes) {
  if (findings.ofac_state === 'match') {
    return 'suspend';
  }

  if (findings.revoked && !findings.reinstated) {
    return 'suspend';
  }

  if (changes.length > 0 || concerns(findings).length > 0) {
    return 'review';
  }

  return 'retain';
}

await withFixtureApi(async client => {
  const runStartedAt = new Date();
  const auditLog = [];
  const batches = batch(portfolio.map(entry => entry.ein));

  heading('Re-verification run');
  field('policy version', POLICY_VERSION);
  field('interval (days)', RE_REVIEW_INTERVAL_DAYS);
  field('organizations', portfolio.length);
  field('batches', batches.length);
  field('started at', runStartedAt.toISOString());

  const records = new Map();
  let lastCheckCount = null;

  for (const [index, eins] of batches.entries()) {
    const result = await client.nonprofits.checkBulk(eins);

    lastCheckCount = result.checkCount;

    for (const org of result.organizations) {
      records.set(org.ein, { org, requestId: result.requestId, status: result.status });
    }

    // An EIN that produced no record is recorded as unverified, not as clean.
    for (const missing of result.notFoundEins) {
      records.set(missing, { org: null, requestId: result.requestId, status: result.status });
    }

    console.log(
      `  batch ${index + 1}: sent ${eins.length}, matched ${result.organizations.length},` +
        ` missing ${result.notFoundEins.length}, request ${result.requestId}`,
    );
  }

  for (const entry of portfolio) {
    const record = records.get(entry.ein);

    heading(`${entry.ein} (onboarded ${entry.onboardedAt})`);

    if (!record?.org) {
      field('outcome', 'review');
      bullet('No record returned. The organization is unverified this cycle, not cleared.');

      auditLog.push({
        ein: entry.ein,
        checkedAt: runStartedAt.toISOString(),
        requestId: record?.requestId ?? null,
        policyVersion: POLICY_VERSION,
        outcome: 'review',
        reason: 'no_record_returned',
        changes: [],
        findings: null,
      });
      continue;
    }

    const findings = collectFindings(record.org, runStartedAt);
    const changes = diffFindings(entry.lastFindings, findings, MATERIAL_FIELDS);
    const openConcerns = concerns(findings);

    // A first run has nothing to compare against; say so rather than reporting
    // every field as "changed".
    const isBaseline = entry.lastFindings === null;

    field('organization', findings.organization_name);
    field('baseline run', isBaseline);
    field('changes since last run', isBaseline ? '<no prior snapshot>' : changes.length);

    if (!isBaseline) {
      for (const change of changes) {
        bullet(`${change.field}: ${render(change.before)} → ${render(change.after)}`);
      }
    }

    field('bmf_status', findings.bmf_status);
    field('pub78_verified', findings.pub78_verified);
    field('revocation_date', findings.revocation_date);
    field('reinstatement_date', findings.reinstatement_date);
    field('ofac state', findings.ofac_state);
    field('conflict flag', findings.irs_bmf_pub78_conflict);
    field('classification', findings.subsection_description);
    field('oldest source (days)', findings.oldest_source_age_days);
    field('report_date', findings.report_date);

    for (const concern of openConcerns) {
      bullet(`concern: ${concern}`);
    }

    const outcome = outcomeFor(findings, isBaseline ? [] : changes);

    field('outcome', outcome);

    // The entry a consultant can produce when asked, months later, why an
    // organization was suspended or retained.
    auditLog.push({
      ein: entry.ein,
      checkedAt: runStartedAt.toISOString(),
      requestId: record.requestId,
      httpStatus: record.status,
      policyVersion: POLICY_VERSION,
      outcome,
      concerns: openConcerns,
      changes: isBaseline ? [] : changes,
      findings,
      nextReviewDue: new Date(
        runStartedAt.getTime() + RE_REVIEW_INTERVAL_DAYS * 86_400_000,
      ).toISOString(),
    });

    // Carry the snapshot forward, so the next run has something to diff against.
    entry.lastFindings = findings;
  }

  heading('Audit log');
  console.log(`  ${'ein'.padEnd(12)} ${'outcome'.padEnd(9)} ${'changes'.padEnd(8)} request`);

  for (const record of auditLog) {
    console.log(
      `  ${record.ein.padEnd(12)} ${record.outcome.padEnd(9)}` +
        ` ${String(record.changes.length).padEnd(8)} ${record.requestId ?? '<none>'}`,
    );
  }

  heading('Run summary');
  field('entries written', auditLog.length);
  field('suspended', auditLog.filter(record => record.outcome === 'suspend').length);
  field('to review', auditLog.filter(record => record.outcome === 'review').length);
  field('retained', auditLog.filter(record => record.outcome === 'retain').length);
  field('checks used this cycle', lastCheckCount);
  field('next run due', auditLog[0]?.nextReviewDue);

  bullet('Request identifiers are stored; API keys are not, and never appear here.');
});

note(
  'The audit trail records what the sources said and which policy read them. It is\n' +
    'evidence of a process, not a legal determination — the SDK supplies the former\n' +
    'and takes no position on the latter.',
);
