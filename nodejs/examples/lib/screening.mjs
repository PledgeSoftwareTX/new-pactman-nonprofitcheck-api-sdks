/**
 * Shared screening helpers for the workflow examples (ex-26 to ex-30).
 *
 * These functions gather what the API said into one object. They do not decide
 * anything: there is no `approved`, no `eligible`, no `safe`. Each workflow
 * applies its own policy to this evidence, and the policies differ on purpose —
 * a donation platform, a DAF and a payout gate reach different conclusions from
 * identical data, and all three are right for their own obligations.
 */
import { getAroe, getBmf, getOfac, getPub78 } from '@pactmandev/nonprofit-check-plus';

/** The four OFAC states from ex-10. `unavailable` is never a pass. */
export function ofacState(nonprofit) {
  const ofac = getOfac(nonprofit);

  if (ofac === null) {
    return 'unavailable';
  }

  if (ofac.status === null || ofac.status === undefined) {
    return 'null';
  }

  if (/UID:/i.test(ofac.status)) {
    return 'match';
  }

  return /NOT included/i.test(ofac.status) ? 'no_match' : 'unrecognized';
}

export function parseApiDate(value) {
  if (!value) {
    return null;
  }

  const parsed = new Date(value);

  return Number.isNaN(parsed.getTime()) ? null : parsed;
}

/** Age in days of the oldest source date on the record, or null if undatable. */
export function oldestSourceAgeDays(nonprofit, now = new Date()) {
  const dates = [
    nonprofit.most_recent_bmf,
    nonprofit.most_recent_pub78,
    nonprofit.ofac_list_published_date,
    nonprofit.aroe_list_published_date,
    nonprofit.organization_info_last_modified,
  ]
    .map(parseApiDate)
    .filter(Boolean);

  if (dates.length === 0) {
    return null;
  }

  const oldest = dates.reduce((worst, date) => (date < worst ? date : worst));

  return Math.round((now.getTime() - oldest.getTime()) / 86_400_000);
}

/**
 * A flat, comparable view of the findings — every value copied from the response.
 *
 * `null` means the API returned null; `undefined` means it returned no such
 * field. Both are preserved so a consumer can tell them apart.
 */
export function collectFindings(nonprofit, now = new Date()) {
  const bmf = getBmf(nonprofit);
  const pub78 = getPub78(nonprofit);
  const aroe = getAroe(nonprofit);

  return {
    ein: nonprofit.ein,
    organization_name: nonprofit.organization_name,
    organization_name_aka: nonprofit.organization_name_aka,

    bmf_returned: bmf !== null,
    bmf_status: bmf?.status,
    exempt_status_code: bmf?.exempt_status_code,
    subsection_description: bmf?.subsection_description,
    foundation_type_code: bmf?.foundation_type_code,
    foundation_type_description: bmf?.foundation_type_description,

    pub78_returned: pub78 !== null,
    pub78_verified: pub78?.verified,
    deductibility_limitations: (pub78?.organization_types ?? [])
      .map(entry => entry.deductibility_limitation)
      .filter(Boolean),

    revocation_code: aroe?.revocation_code,
    revocation_date: aroe?.revocation_date,
    reinstatement_date: aroe?.reinstatement_date,
    revoked: Boolean(aroe?.revocation_code || aroe?.revocation_date),
    reinstated: Boolean(aroe?.reinstatement_date),

    ofac_state: ofacState(nonprofit),
    ofac_status: nonprofit.ofac_status,

    irs_bmf_pub78_conflict: nonprofit.irs_bmf_pub78_conflict,

    report_date: nonprofit.report_date,
    organization_info_last_modified: nonprofit.organization_info_last_modified,
    oldest_source_age_days: oldestSourceAgeDays(nonprofit, now),
  };
}

/** Human-readable reasons a workflow might want to stop. No verdict attached. */
export function concerns(findings, { staleAfterDays = 120 } = {}) {
  const found = [];

  if (findings.revoked && !findings.reinstated) {
    found.push('listed in the IRS Automatic Revocation data with no reinstatement');
  }

  if (findings.revoked && findings.reinstated) {
    found.push('revoked and later reinstated — the lapse period may still matter');
  }

  if (findings.ofac_state === 'match') {
    found.push('a possible OFAC SDN match was reported');
  }

  if (findings.ofac_state !== 'no_match' && findings.ofac_state !== 'match') {
    found.push(`OFAC screening result is ${findings.ofac_state} — nothing was cleared`);
  }

  if (findings.irs_bmf_pub78_conflict === true) {
    found.push('the BMF and Publication 78 disagree about this organization');
  }

  if (findings.bmf_status === false) {
    found.push('the BMF does not show the organization as exempt');
  }

  if (findings.pub78_verified === false) {
    found.push('the organization is not listed in Publication 78');
  }

  if (!findings.bmf_returned) {
    found.push('no BMF data was returned');
  }

  if (!findings.pub78_returned) {
    found.push('no Publication 78 data was returned');
  }

  if (findings.oldest_source_age_days === null) {
    found.push('no source date was returned, so data age cannot be established');
  } else if (findings.oldest_source_age_days > staleAfterDays) {
    found.push(`the oldest source is ${findings.oldest_source_age_days} days old`);
  }

  return found;
}

/** Fields worth diffing between two checks of the same organization. */
export const MATERIAL_FIELDS = [
  'organization_name',
  'bmf_status',
  'exempt_status_code',
  'pub78_verified',
  'revocation_code',
  'revocation_date',
  'reinstatement_date',
  'ofac_state',
  'irs_bmf_pub78_conflict',
  'foundation_type_code',
  'subsection_description',
];

/** Changes between a stored set of findings and a fresh one. */
export function diffFindings(previous, current, fields = MATERIAL_FIELDS) {
  const changes = [];

  for (const key of fields) {
    const before = previous?.[key];
    const after = current?.[key];

    if (JSON.stringify(before) !== JSON.stringify(after)) {
      changes.push({ field: key, before, after });
    }
  }

  return changes;
}
