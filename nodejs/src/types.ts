/**
 * Response models.
 *
 * Field names mirror the wire format exactly, so what you read in the Pactman
 * API reference is what you access in code — no rename table to keep in sync.
 *
 * Every field is optional at the type level. The API omits fields it has no data
 * for, and an index signature keeps fields added by future API versions readable
 * through {@link Nonprofit} without a deserialization failure or an SDK upgrade.
 */

/** A deductibility entry from IRS Publication 78. */
export interface OrganizationType {
  organization_type?: string | null;
  deductibility_limitation?: string | null;
  deductibility_status_description?: string | null;
  [key: string]: unknown;
}

/**
 * A nonprofit record as returned by the US nonprofit check endpoints.
 *
 * Source-specific findings are flat on this object, prefixed by source
 * (`pub78_*`, `bmf_*`, `ofac_*`, and the revocation fields for the IRS
 * Automatic Revocation of Exemption list). See `sources.ts` for grouped views.
 */
export interface Nonprofit {
  /** Public Pactman profile URL for the organization. */
  pactman_org_url?: string | null;
  organization_info_last_modified?: string | null;

  ein?: string | null;
  organization_name?: string | null;
  organization_name_aka?: string | null;
  address_line1?: string | null;
  address_line2?: string | null;
  city?: string | null;
  state?: string | null;
  state_name?: string | null;
  zip?: string | null;
  filing_req_code?: string | null;

  // IRS Publication 78
  pub78_church_message?: string | null;
  pub78_organization_name?: string | null;
  pub78_ein?: string | null;
  pub78_verified?: boolean | null;
  pub78_city?: string | null;
  pub78_state?: string | null;
  pub78_indicator?: string | null;
  pub78_source_org_type_1?: string | null;
  pub78_source_org_type_2?: string | null;
  pub78_source_org_type_3?: string | null;
  organization_types?: OrganizationType[] | null;
  most_recent_pub78?: string | null;

  // IRS Business Master File
  bmf_church_message?: string | null;
  bmf_organization_name?: string | null;
  bmf_ein?: string | null;
  bmf_status?: boolean | null;
  bmf_city?: string | null;
  bmf_state?: string | null;
  bmf_street_address?: string | null;
  bmf_subsection?: string | null;
  bmf_source_pf_filing_req_cd?: string | null;
  bmf_deductability_text?: string | null;
  most_recent_bmf?: string | null;
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

  /**
   * OFAC Specially Designated Nationals finding.
   *
   * The API returns a sentence, not a flag — do not pattern-match it to derive a
   * boolean. Read it, or present it to a reviewer.
   */
  ofac_status?: string | null;
  ofac_list_published_date?: string | null;

  // IRS Automatic Revocation of Exemption
  revocation_code?: string | null;
  revocation_date?: string | null;
  reinstatement_date?: string | null;
  aroe_list_published_date?: string | null;

  /** True when the IRS BMF and Publication 78 records disagree. */
  irs_bmf_pub78_conflict?: boolean | null;
  report_date?: string | null;

  /** Fields introduced by a newer API version than this SDK knows about. */
  [key: string]: unknown;
}

/** One entry from the envelope's `errors` array. */
export interface ApiErrorDetail {
  /** The API resource the error came from. */
  resource?: string;
  /** Human-readable explanation. */
  reason?: string;
  /** Status code for this specific failure, which may differ from the HTTP status. */
  code?: number;
  /** EINs this error applies to, for bulk requests. */
  eins?: string[] | string;
  [key: string]: unknown;
}

/** The envelope every nonprofit check response is wrapped in. */
export interface ApiEnvelope<TData> {
  code?: number;
  message?: string;
  /**
   * Item-level failures. Present on successful responses too — a bulk request
   * where some EINs were not found returns HTTP 200 with entries here.
   */
  errors?: ApiErrorDetail[] | string | null;
  data?: TData;
  /** Server-side processing time in milliseconds. */
  timeTaken?: number | null;
  /** Checks this request consumed from the account's quota. */
  nonprofit_check_count?: number | null;
  [key: string]: unknown;
}

/** Fields shared by every result this SDK returns. */
export interface PactmanResult<TRaw> {
  /** Checks this request consumed from the account's quota, when reported. */
  checkCount: number | null;
  /** Server-side processing time in milliseconds, when reported. */
  timeTakenMs: number | null;
  /**
   * Item-level failures reported alongside a successful response. Empty when
   * the API reported none.
   */
  errors: ApiErrorDetail[];
  /** Correlation identifier from the response headers, when the server sent one. */
  requestId: string | null;
  /** HTTP status of the response. */
  status: number;
  /** The unmodified parsed response body, including any fields not typed above. */
  raw: TRaw;
}

/** The result of {@link import('./client.js').NonprofitsResource.check}. */
export interface SingleCheckResult extends PactmanResult<ApiEnvelope<Nonprofit | null>> {
  /** The organization, or `null` when the API returned no record. */
  nonprofit: Nonprofit | null;
}

/** The result of {@link import('./client.js').NonprofitsResource.checkBulk}. */
export interface BulkCheckResult extends PactmanResult<ApiEnvelope<Nonprofit[] | null>> {
  /** Organizations the API matched, in the order it returned them. */
  organizations: Nonprofit[];
  /**
   * EINs the API reported no record for, collected from `errors`.
   *
   * A bulk request where some EINs miss is a successful HTTP 200, not an error.
   */
  notFoundEins: string[];
}
