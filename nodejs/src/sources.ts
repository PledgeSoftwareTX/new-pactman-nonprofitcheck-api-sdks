/**
 * Grouped views over the source-specific findings on a {@link Nonprofit}.
 *
 * These are projections, not derivations: every property is copied 1:1 from a
 * field the API returned. Nothing here computes an "approved", "eligible" or
 * "safe" verdict, and nothing infers a value from another field.
 *
 * Each accessor returns `null` when the API returned no data at all for that
 * source. That keeps "the source was not returned" distinguishable from an
 * explicit negative such as `pub78_verified: false` or a `null` field.
 */

import type { Nonprofit, OrganizationType } from './types.js';

/** IRS Publication 78 findings. */
export interface Pub78Source {
  verified?: boolean | null;
  organization_name?: string | null;
  ein?: string | null;
  city?: string | null;
  state?: string | null;
  indicator?: string | null;
  church_message?: string | null;
  source_org_type_1?: string | null;
  source_org_type_2?: string | null;
  source_org_type_3?: string | null;
  organization_types?: OrganizationType[] | null;
  most_recent?: string | null;
}

/** IRS Business Master File findings. */
export interface BmfSource {
  status?: boolean | null;
  organization_name?: string | null;
  ein?: string | null;
  city?: string | null;
  state?: string | null;
  street_address?: string | null;
  church_message?: string | null;
  subsection?: string | null;
  subsection_description?: string | null;
  foundation_code?: string | null;
  foundation_code_description?: string | null;
  foundation_type_code?: string | null;
  foundation_type_description?: string | null;
  foundation_509a_status?: string | null;
  ruling_month?: string | null;
  ruling_year?: string | null;
  group_exemption?: string | null;
  exempt_status_code?: string | null;
  filing_req_code?: string | null;
  pf_filing_req_cd?: string | null;
  deductability_text?: string | null;
  most_recent?: string | null;
}

/** IRS Automatic Revocation of Exemption findings. */
export interface AroeSource {
  revocation_code?: string | null;
  revocation_date?: string | null;
  reinstatement_date?: string | null;
  list_published_date?: string | null;
}

/** OFAC Specially Designated Nationals findings. */
export interface OfacSource {
  /**
   * The finding as the API phrases it. This is prose, not a flag; the API does
   * not currently return a boolean match indicator, and this SDK does not
   * invent one by matching on the wording.
   */
  status?: string | null;
  list_published_date?: string | null;
}

/** Publication 78 findings, or `null` if the API returned none. */
export function getPub78(nonprofit: Nonprofit): Pub78Source | null {
  return project<Pub78Source>(nonprofit, {
    verified: 'pub78_verified',
    organization_name: 'pub78_organization_name',
    ein: 'pub78_ein',
    city: 'pub78_city',
    state: 'pub78_state',
    indicator: 'pub78_indicator',
    church_message: 'pub78_church_message',
    source_org_type_1: 'pub78_source_org_type_1',
    source_org_type_2: 'pub78_source_org_type_2',
    source_org_type_3: 'pub78_source_org_type_3',
    organization_types: 'organization_types',
    most_recent: 'most_recent_pub78',
  });
}

/** Business Master File findings, or `null` if the API returned none. */
export function getBmf(nonprofit: Nonprofit): BmfSource | null {
  return project<BmfSource>(nonprofit, {
    status: 'bmf_status',
    organization_name: 'bmf_organization_name',
    ein: 'bmf_ein',
    city: 'bmf_city',
    state: 'bmf_state',
    street_address: 'bmf_street_address',
    church_message: 'bmf_church_message',
    subsection: 'bmf_subsection',
    subsection_description: 'subsection_description',
    foundation_code: 'foundation_code',
    foundation_code_description: 'foundation_code_description',
    foundation_type_code: 'foundation_type_code',
    foundation_type_description: 'foundation_type_description',
    foundation_509a_status: 'foundation_509a_status',
    ruling_month: 'ruling_month',
    ruling_year: 'ruling_year',
    group_exemption: 'group_exemption',
    exempt_status_code: 'exempt_status_code',
    filing_req_code: 'filing_req_code',
    pf_filing_req_cd: 'bmf_source_pf_filing_req_cd',
    deductability_text: 'bmf_deductability_text',
    most_recent: 'most_recent_bmf',
  });
}

/** Automatic Revocation of Exemption findings, or `null` if the API returned none. */
export function getAroe(nonprofit: Nonprofit): AroeSource | null {
  return project<AroeSource>(nonprofit, {
    revocation_code: 'revocation_code',
    revocation_date: 'revocation_date',
    reinstatement_date: 'reinstatement_date',
    list_published_date: 'aroe_list_published_date',
  });
}

/** OFAC findings, or `null` if the API returned none. */
export function getOfac(nonprofit: Nonprofit): OfacSource | null {
  return project<OfacSource>(nonprofit, {
    status: 'ofac_status',
    list_published_date: 'ofac_list_published_date',
  });
}

/**
 * Copies the mapped fields onto a new object, preserving `null` and `false`.
 *
 * Returns `null` only when every mapped field is absent from the response, which
 * is how "this source was not returned" is represented.
 */
function project<TShape>(
  nonprofit: Nonprofit,
  mapping: Record<keyof TShape & string, string>,
): TShape | null {
  const result: Record<string, unknown> = {};
  let present = false;

  for (const [target, wireField] of Object.entries(mapping) as Array<[string, string]>) {
    if (wireField in nonprofit && nonprofit[wireField] !== undefined) {
      result[target] = nonprofit[wireField];
      present = true;
    }
  }

  return present ? (result as TShape) : null;
}
