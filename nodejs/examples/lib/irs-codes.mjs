/**
 * Local lookup tables for IRS codes the API returns without a description.
 *
 * The API already describes most classifications for you — `subsection_description`,
 * `foundation_code_description`, `foundation_type_description`. Prefer those:
 * they come from the source and change with it. Only fields returned as a bare
 * code need a table, and a table you own is a table you have to maintain.
 *
 * Two rules make that safe:
 *
 *   1. Every lookup has an unknown-value fallback that keeps the original code
 *      visible, so a value added by the IRS degrades to "code 42, meaning
 *      unknown to this application" rather than to `undefined` or a wrong label.
 *   2. `null` is reported as `null`, never as an unknown code.
 *
 * Verify these against the current IRS Exempt Organizations Business Master File
 * data dictionary and Publication 78 documentation before relying on them for a
 * policy decision.
 */

/** IRS EO BMF `FILING_REQ_CD` — which annual return the organization files. */
const FILING_REQUIREMENT = {
  '00': 'No 990 return required',
  '01': 'Form 990 or 990-EZ required',
  '02': 'Form 990-N (e-Postcard) required',
  '03': 'Group return',
  '04': 'Form 990-BL required (black lung trust)',
  '06': 'Not required to file (church)',
  '07': 'Government 501(c)(1)',
  '13': 'Not required to file (religious organization)',
  '14': 'Not required to file (state instrumentality)',
};

/** IRS EO BMF `PF_FILING_REQ_CD` — whether a 990-PF is required. */
const PF_FILING_REQUIREMENT = {
  '0': 'No 990-PF return required',
  '1': 'Form 990-PF required',
};

/** IRS EO BMF `STATUS` — the exemption status the BMF carries. */
const EXEMPT_STATUS = {
  '01': 'Unconditional exemption',
  '02': 'Conditional exemption',
  '12': 'Trust described in section 4947(a)(2)',
  '25': 'Organization terminated',
};

/** Publication 78 deductibility status codes. */
const DEDUCTIBILITY_STATUS = {
  PC: 'Public charity',
  POF: 'Private operating foundation',
  PF: 'Private foundation',
  SO: 'Supporting organization',
  SOUNK: 'Supporting organization, type not determined',
  LODGE: 'Domestic fraternal society',
  FORGN: 'Foreign organization',
  GROUP: 'Subordinate organization in a group ruling',
  EO: 'Exempt organization, other',
};

function lookup(table, code, label) {
  if (code === null || code === undefined) {
    return { code, known: false, description: null, display: code === null ? '<null>' : '<not returned>' };
  }

  const description = table[code];

  if (description === undefined) {
    // A code this application has never seen. Keep it legible and keep it
    // flagged; do not guess, and do not drop it.
    return {
      code,
      known: false,
      description: null,
      display: `${code} — unrecognized ${label} code, not interpreted`,
    };
  }

  return { code, known: true, description, display: `${code} — ${description}` };
}

export const describeFilingRequirement = code => lookup(FILING_REQUIREMENT, code, 'filing requirement');
export const describePfFilingRequirement = code =>
  lookup(PF_FILING_REQUIREMENT, code, 'private foundation filing requirement');
export const describeExemptStatus = code => lookup(EXEMPT_STATUS, code, 'exempt status');
export const describeDeductibilityStatus = code =>
  lookup(DEDUCTIBILITY_STATUS, code, 'deductibility status');

/** `ruling_month` + `ruling_year` as one value, without inventing a date. */
export function formatRulingDate(month, year) {
  if (!year) {
    return year === null ? '<null>' : '<not returned>';
  }

  return month ? `${year}-${String(month).padStart(2, '0')}` : String(year);
}
