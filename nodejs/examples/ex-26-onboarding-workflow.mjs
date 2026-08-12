/**
 * EX-26 — Donation-platform onboarding workflow.
 *
 * The end-to-end shape: an applicant supplies an EIN, a legal name and an
 * address; one check gathers BMF, Publication 78, revocation, OFAC, conflict and
 * freshness findings; the platform routes the applicant.
 *
 * The routing rules below belong to this fictional platform. Read them as an
 * illustration of where your policy lives, not as a policy to adopt. The SDK
 * contributes evidence and stops there — it never produces the decision.
 *
 * Run:  PACTMAN_API_KEY=... node examples/ex-26-onboarding-workflow.mjs
 */
import { FIXTURE_EINS, withFixtureApi } from './lib/fixture-api.mjs';
import { bullet, field, heading, note } from './lib/print.mjs';
import { compareAddressField, compareName, isAgreement, normalizeZip } from './lib/matching.mjs';
import { collectFindings, concerns } from './lib/screening.mjs';

/** This platform's rules, in one place, reviewable by its compliance team. */
const POLICY = {
  staleAfterDays: 120,
  requirePub78Listing: true,
  autoRejectOn: ['revoked_not_reinstated', 'ofac_match'],
  addressComponents: ['address_line1', 'city', 'state', 'zip'],
};

const applicants = [
  {
    ein: FIXTURE_EINS.publicCharity,
    legalName: 'Meals Today Example Nonprofit, Inc.',
    address: { address_line1: '50 Lowell Ave', city: 'Westfield', state: 'MA', zip: '01085' },
  },
  {
    ein: FIXTURE_EINS.revoked,
    legalName: 'Lapsed Filings Example Society',
    address: { address_line1: '50 Lowell Ave', city: 'Westfield', state: 'MA', zip: '01085' },
  },
  {
    ein: FIXTURE_EINS.ofacMatch,
    legalName: 'Overseas Relief Example Fund',
    address: { address_line1: '50 Lowell Ave', city: 'Westfield', state: 'MA', zip: '01085' },
  },
  {
    ein: FIXTURE_EINS.conflicted,
    legalName: 'Crosscheck Example Institute',
    address: { address_line1: '50 Lowell Ave', city: 'Westfield', state: 'MA', zip: '01085' },
  },
  {
    ein: FIXTURE_EINS.noRecord,
    legalName: 'Unlisted Example Org',
    address: { address_line1: '1 Main St', city: 'Boston', state: 'MA', zip: '02108' },
  },
];

/** Applies POLICY to the gathered evidence. Returns a route and its reasons. */
function route({ findings, nameComparison, addressOutcomes, issues }) {
  const reasons = [...issues];

  if (findings.revoked && !findings.reinstated) {
    return { decision: 'reject', reasons: ['Exemption revoked with no reinstatement.', ...reasons] };
  }

  if (findings.ofac_state === 'match') {
    return { decision: 'reject', reasons: ['Possible OFAC SDN match.', ...reasons] };
  }

  if (!isAgreement(nameComparison.outcome)) {
    reasons.push(`Submitted name did not match an IRS-held name (${nameComparison.outcome}).`);
  }

  const addressConflicts = POLICY.addressComponents.filter(
    component => addressOutcomes[component] === 'mismatch',
  );

  if (addressConflicts.length > 0) {
    reasons.push(`Address components disagree: ${addressConflicts.join(', ')}.`);
  }

  if (POLICY.requirePub78Listing && findings.pub78_verified !== true) {
    reasons.push('Not listed in Publication 78, which this platform requires.');
  }

  return reasons.length === 0
    ? { decision: 'approve', reasons: ['Every check this platform requires was satisfied.'] }
    : { decision: 'manual_review', reasons };
}

await withFixtureApi(async client => {
  const outcomes = [];

  for (const applicant of applicants) {
    heading(`Applicant ${applicant.ein} — ${applicant.legalName}`);

    let result;

    try {
      result = await client.nonprofits.check(applicant.ein);
    } catch (error) {
      // A failed lookup is not a rejection. Nothing was learned, so nothing can
      // be concluded — the applicant waits, they are not turned away.
      field('lookup', `failed: ${error.constructor.name} (${error.category})`);
      field('decision', 'manual_review — the check could not be completed');
      outcomes.push({ ein: applicant.ein, decision: 'manual_review' });
      continue;
    }

    if (!result.nonprofit) {
      field('decision', 'manual_review — no record returned for this EIN');
      outcomes.push({ ein: applicant.ein, decision: 'manual_review' });
      continue;
    }

    const { nonprofit } = result;
    const findings = collectFindings(nonprofit);
    const issues = concerns(findings, { staleAfterDays: POLICY.staleAfterDays });

    const nameComparison = compareName(applicant.legalName, {
      organization_name: nonprofit.organization_name,
      organization_name_aka: nonprofit.organization_name_aka,
    });

    const addressOutcomes = {};

    for (const component of POLICY.addressComponents) {
      addressOutcomes[component] = compareAddressField(
        applicant.address[component],
        nonprofit[component],
        component === 'zip' ? normalizeZip : undefined,
      ).outcome;
    }

    field('IRS name', nonprofit.organization_name);
    field('name comparison', nameComparison.outcome);
    field('address comparison', Object.entries(addressOutcomes).map(([k, v]) => `${k}=${v}`).join(' '));
    field('bmf_status', findings.bmf_status);
    field('pub78_verified', findings.pub78_verified);
    field('revoked / reinstated', `${findings.revoked} / ${findings.reinstated}`);
    field('ofac state', findings.ofac_state);
    field('irs_bmf_pub78_conflict', findings.irs_bmf_pub78_conflict);
    field('oldest source age (days)', findings.oldest_source_age_days);

    const decision = route({ findings, nameComparison, addressOutcomes, issues });

    field('decision', decision.decision);

    for (const reason of decision.reasons) {
      bullet(reason);
    }

    // The record that makes the decision explainable months later.
    outcomes.push({
      ein: applicant.ein,
      decision: decision.decision,
      reasons: decision.reasons,
      checkedAt: new Date().toISOString(),
      requestId: result.requestId,
      findings,
    });
  }

  heading('Onboarding queue');

  for (const outcome of outcomes) {
    console.log(`  ${outcome.ein}  ${outcome.decision}`);
  }
});

note(
  'The platform decided; the SDK did not. Nothing in this package returns approve,\n' +
    'reject, eligible or safe, and no combination of the fields above constitutes a\n' +
    'compliance determination on its own.',
);
