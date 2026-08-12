/**
 * Name and address comparison for the onboarding examples.
 *
 * None of this is part of the SDK, and deliberately so. The API returns the
 * identity IRS records hold; deciding whether "St. Mary's Hosp" and "SAINT MARYS
 * HOSPITAL INC" are the same applicant is a customer policy question, and the
 * answer differs between a donation platform, a DAF and a payroll-giving system.
 *
 * The comparisons below are conservative on purpose:
 *
 *   - punctuation, casing, spacing and common abbreviations are not differences
 *   - a value the API did not return is never scored as agreement
 *   - the outcome is a routing hint, never a fraud finding
 */

/** Legal suffixes that carry no identifying information. */
const LEGAL_SUFFIXES = new Set(['INC', 'INCORPORATED', 'LLC', 'LTD', 'CO', 'CORP', 'CORPORATION']);

/** Abbreviations seen in IRS records versus what applicants type. */
const ABBREVIATIONS = new Map([
  ['&', 'AND'],
  ['ASSN', 'ASSOCIATION'],
  ['ASSOC', 'ASSOCIATION'],
  ['CTR', 'CENTER'],
  ['CENTRE', 'CENTER'],
  ['FDN', 'FOUNDATION'],
  ['FND', 'FOUNDATION'],
  ['INTL', 'INTERNATIONAL'],
  ['NATL', 'NATIONAL'],
  ['ORG', 'ORGANIZATION'],
  ['SOC', 'SOCIETY'],
  ['ST', 'SAINT'],
  ['UNIV', 'UNIVERSITY'],
  ['DEPT', 'DEPARTMENT'],
  ['MT', 'MOUNT'],
]);

/** Street-type abbreviations, for address lines. */
const STREET_TYPES = new Map([
  ['STREET', 'ST'],
  ['AVENUE', 'AVE'],
  ['ROAD', 'RD'],
  ['BOULEVARD', 'BLVD'],
  ['DRIVE', 'DR'],
  ['LANE', 'LN'],
  ['SUITE', 'STE'],
  ['APARTMENT', 'APT'],
  ['NORTH', 'N'],
  ['SOUTH', 'S'],
  ['EAST', 'E'],
  ['WEST', 'W'],
  ['POST OFFICE BOX', 'PO BOX'],
]);

function words(value) {
  return String(value)
    .toUpperCase()
    .replace(/&/g, ' & ')
    .replace(/[^A-Z0-9&]+/g, ' ')
    .trim()
    .split(' ')
    .filter(Boolean);
}

/** Uppercase, punctuation-free, abbreviation-expanded, suffix-free. */
export function normalizeName(value) {
  if (value === null || value === undefined) {
    return null;
  }

  const expanded = words(value).map(word => ABBREVIATIONS.get(word) ?? word);

  while (expanded.length > 1 && LEGAL_SUFFIXES.has(expanded.at(-1))) {
    expanded.pop();
  }

  return expanded.join(' ');
}

/** Uppercase, punctuation-free, street types abbreviated to the USPS short form. */
export function normalizeAddressLine(value) {
  if (value === null || value === undefined) {
    return null;
  }

  let text = String(value).toUpperCase();

  for (const [long, short] of STREET_TYPES) {
    text = text.replace(new RegExp(`\\b${long}\\b`, 'g'), short);
  }

  return text.replace(/[^A-Z0-9]+/g, ' ').trim();
}

/** ZIP+4 and ZIP5 compare on the five-digit prefix. */
export function normalizeZip(value) {
  if (value === null || value === undefined) {
    return null;
  }

  const digits = String(value).replace(/\D/g, '');

  return digits === '' ? null : digits.slice(0, 5);
}

/**
 * Compares a submitted name against the names the API returned.
 *
 * @returns `exact` | `normalized` | `mismatch` | `not_returned`, plus the field
 * that matched and the normalized forms, so a reviewer can see the reasoning.
 */
export function compareName(submitted, candidates) {
  const target = normalizeName(submitted);
  const comparable = Object.entries(candidates).filter(([, value]) => value !== null && value !== undefined);

  if (comparable.length === 0) {
    return { outcome: 'not_returned', matchedField: null, submitted: target, candidates: [] };
  }

  const normalized = comparable.map(([source, value]) => ({
    source,
    value,
    normalized: normalizeName(value),
  }));

  const exact = normalized.find(entry => entry.value === submitted);

  if (exact) {
    return { outcome: 'exact', matchedField: exact.source, submitted: target, candidates: normalized };
  }

  const equivalent = normalized.find(entry => entry.normalized === target);

  if (equivalent) {
    return {
      outcome: 'normalized',
      matchedField: equivalent.source,
      submitted: target,
      candidates: normalized,
    };
  }

  return { outcome: 'mismatch', matchedField: null, submitted: target, candidates: normalized };
}

/**
 * Compares one address component.
 *
 * `not_returned` is its own outcome. Treating an absent city as a matching city
 * is the quiet failure this function exists to prevent.
 */
export function compareAddressField(submitted, returned, normalize = normalizeAddressLine) {
  if (returned === null || returned === undefined) {
    return { outcome: 'not_returned', submitted, returned };
  }

  if (submitted === null || submitted === undefined || String(submitted).trim() === '') {
    return { outcome: 'not_submitted', submitted, returned };
  }

  if (submitted === returned) {
    return { outcome: 'exact', submitted, returned };
  }

  return {
    outcome: normalize(submitted) === normalize(returned) ? 'normalized' : 'mismatch',
    submitted,
    returned,
  };
}

/** True for outcomes that agree, however loosely. Absence never counts. */
export function isAgreement(outcome) {
  return outcome === 'exact' || outcome === 'normalized';
}
