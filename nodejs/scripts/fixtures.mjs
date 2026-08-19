/**
 * Fixture organizations for the examples and the mock server.
 *
 * Scenarios like a revoked exemption, an OFAC match, a cross-source conflict or
 * an unknown future field cannot be summoned on demand from the production API.
 * They are declared here once so an example can demonstrate the handling and the
 * mock server can serve the record.
 *
 * Field names and values mirror the shapes documented in the Pactman API
 * reference. The EINs are illustrative and are not real organizations.
 */
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

/** The two OFAC sentences the API returns. It reports prose, not a boolean. */
export const OFAC_NO_MATCH =
  'This organization was NOT included in the Office of Foreign Assets Control Specially Designated Nationals (SDN) list.';

export const OFAC_POSSIBLE_MATCH =
  'This organization may be included in the Office of Foreign Assets Control Specially Designated Nationals(SDN) list. ' +
  'A close match was found with the Special Designated National with UID: 41234';

/** Named EINs the examples refer to, so no example hard-codes a bare number. */
export const FIXTURE_EINS = {
  /** A 501(c)(3) public charity with every source returned and nothing adverse. */
  publicCharity: '411787097',
  /** A second clean organization, for bulk examples. */
  publicCharitySecond: '996589560',
  /** A 501(c)(3) private foundation — different foundation and filing codes. */
  privateFoundation: '042103594',
  /** A record with most optional identity fields returned as null. */
  sparseIdentity: '060646700',
  /** Address fields that are present but disagree with each other. */
  inconsistentAddress: '311580204',
  /** Every source date is old, for the freshness and re-review examples. */
  staleData: '362167048',
  /** Listed in the IRS Automatic Revocation of Exemption data, not reinstated. */
  revoked: '237112796',
  /** Revoked and subsequently reinstated — both dates present. */
  reinstated: '133039601',
  /** A possible OFAC SDN match. */
  ofacMatch: '954367818',
  /** OFAC screening returned no value for this organization. */
  ofacUnavailable: '061553389',
  /** BMF and Publication 78 disagree; `irs_bmf_pub78_conflict` is true. */
  conflicted: '521693387',
  /** Carries fields and an enum value this SDK version does not know about. */
  futureFields: '237324370',
  /** Well-formed, but no record exists. */
  noRecord: '999999999',
};

/**
 * The API formats every date as `M/DD/YYYY h:mm:ss AM`. Fixture dates are
 * generated relative to today so the freshness examples stay meaningful however
 * long after they were written they are run.
 */
export function apiDate(daysAgo) {
  const date = new Date(Date.now() - daysAgo * 86_400_000);
  const time = date.toLocaleTimeString('en-US', { hour12: true });

  return `${date.getMonth() + 1}/${String(date.getDate()).padStart(2, '0')}/${date.getFullYear()} ${time}`;
}

/** EINs the mock server answers with a specific failure, for the error examples. */
export const CONTROL_EINS = {
  /** Always answers HTTP 429 with `Retry-After: 1`. */
  rateLimited: '900000429',
  /** Answers HTTP 503 twice per client, then succeeds. */
  transientFailure: '900000503',
  /** Holds the response open, so a short timeout expires. */
  slow: '900000408',
};

const DEDUCTIBILITY_PUBLIC_CHARITY = {
  organization_type:
    'Deductions for donations to public charities are generally limited to 50 percent of adjusted gross income (AGI). ' +
    'This limit increases to 60% of AGI for cash donations. For Non-Cash assets held for more than one year, the limit is 30% of AGI.',
  deductibility_limitation: '50%',
  deductibility_status_description: 'PC',
};

const DEDUCTIBILITY_PRIVATE_FOUNDATION = {
  organization_type:
    'Deductions for donations to private foundations are generally limited to 30 percent of adjusted gross income (AGI). ' +
    'For Non-Cash assets held for more than one year, the limit is 20% of AGI.',
  deductibility_limitation: '30%',
  deductibility_status_description: 'PF',
};

function slug(name) {
  return name.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '');
}

/**
 * A complete, unremarkable public charity. Scenarios override from here.
 *
 * @param omit Keys to delete outright, so the record can express "the API
 * returned no field at all" as distinct from "the API returned null".
 */
function publicCharity(ein, name, overrides = {}, omit = []) {
  const organization = {
    pactman_org_url: `https://pactman.org/profile/nonprofit/${slug(name)}-${ein.slice(-4)}`,
    organization_info_last_modified: apiDate(40),

    ein,
    organization_name: name.toUpperCase(),
    organization_name_aka: null,
    address_line1: '50 LOWELL AVE',
    address_line2: 'APT 3B',
    city: 'WESTFIELD',
    state: 'MA',
    state_name: 'Massachusetts',
    zip: '01085-2643',
    filing_req_code: '01',

    pub78_church_message: null,
    pub78_organization_name: name,
    pub78_ein: ein,
    pub78_verified: true,
    pub78_city: 'Westfield',
    pub78_state: 'MA',
    pub78_indicator: '0',
    pub78_source_org_type_1: 'PC',
    pub78_source_org_type_2: null,
    pub78_source_org_type_3: null,
    organization_types: [DEDUCTIBILITY_PUBLIC_CHARITY],
    most_recent_pub78: apiDate(26),

    bmf_church_message: null,
    bmf_organization_name: name.toUpperCase(),
    bmf_ein: ein,
    bmf_status: true,
    bmf_city: 'WESTFIELD',
    bmf_state: 'MA',
    bmf_street_address: '50 LOWELL AVE APT 3B',
    bmf_subsection: '03',
    bmf_source_pf_filing_req_cd: '0',
    bmf_deductability_text: 'Contributions are deductible',
    most_recent_bmf: apiDate(20),
    subsection_description: '501(c)(3) Public Charity',
    foundation_code: '10',
    foundation_code_description: 'Public charity described in section 509(a)(1) or (2)',
    foundation_type_code: 'pc',
    foundation_type_description: 'Public charity described in section 509(a)(1) or (2)',
    foundation_509a_status: 'N/A',
    ruling_month: '07',
    ruling_year: '2024',
    group_exemption: '0000',
    exempt_status_code: '01',

    ofac_status: OFAC_NO_MATCH,
    ofac_list_published_date: apiDate(5),

    revocation_code: null,
    revocation_date: null,
    reinstatement_date: null,
    aroe_list_published_date: apiDate(12),

    irs_bmf_pub78_conflict: false,
    report_date: apiDate(0),

    ...overrides,
  };

  for (const key of omit) {
    delete organization[key];
  }

  return organization;
}

/** Every organization the mock server can return, keyed by EIN. */
export const FIXTURE_ORGANIZATIONS = {
  [FIXTURE_EINS.publicCharity]: publicCharity(
    FIXTURE_EINS.publicCharity,
    'Meals Today Example Nonprofit',
    {
      organization_name_aka: 'MEALS TODAY E.N',
      pub78_organization_name: 'Meals Today Example Nonprofit, Inc.',
    },
  ),

  [FIXTURE_EINS.publicCharitySecond]: publicCharity(
    FIXTURE_EINS.publicCharitySecond,
    'Aborjaily Example Nonprofit',
    {
      organization_name_aka: 'ABORJAILY E.N',
      city: 'SPRINGFIELD',
      pub78_city: 'Springfield',
      zip: '01103-1420',
      address_line1: '19 HAMPDEN ST',
      address_line2: null,
      bmf_street_address: '19 HAMPDEN ST',
    },
  ),

  [FIXTURE_EINS.privateFoundation]: publicCharity(
    FIXTURE_EINS.privateFoundation,
    'Hartwell Family Example Foundation',
    {
      organization_name_aka: null,
      // A private foundation files a 990-PF, tracked in the PF field below
      // rather than in the general 990 filing requirement.
      filing_req_code: '00',
      pub78_source_org_type_1: 'PF',
      organization_types: [DEDUCTIBILITY_PRIVATE_FOUNDATION],
      bmf_source_pf_filing_req_cd: '1',
      bmf_deductability_text: 'Contributions are deductible',
      subsection_description: '501(c)(3) Private Foundation',
      foundation_code: '04',
      foundation_code_description: 'Private non-operating foundation',
      foundation_type_code: 'pf',
      foundation_type_description: 'Private non-operating foundation',
      foundation_509a_status: 'N/A',
      ruling_month: '11',
      ruling_year: '1998',
    },
  ),

  // Optional identity fields the API had no value for. `null` here means "the
  // API returned no value", which is not the same as "this did not match".
  [FIXTURE_EINS.sparseIdentity]: publicCharity(
    FIXTURE_EINS.sparseIdentity,
    'Quiet Harbor Example Trust',
    {
      organization_name_aka: null,
      address_line1: 'PO BOX 118',
      address_line2: null,
      city: 'ROCKPORT',
      state: 'ME',
      state_name: null,
      zip: null,
      pub78_city: null,
      pub78_state: null,
      bmf_city: null,
      bmf_state: null,
      bmf_street_address: null,
      group_exemption: null,
      ruling_month: null,
      ruling_year: null,
    },
    // No OFAC keys at all: the source was not reported for this organization,
    // which is not the same as a null status or a no-match result.
    ['ofac_status', 'ofac_list_published_date'],
  ),

  // Every address component is present, and they contradict one another: the
  // state code says Massachusetts, the state name and the ZIP say Maine, and
  // address_line2 holds a placeholder. Transcription damage of this kind
  // survives any check that only asks whether a field came back non-null.
  [FIXTURE_EINS.inconsistentAddress]: publicCharity(
    FIXTURE_EINS.inconsistentAddress,
    'Harbor Light Example Alliance',
    {
      organization_name_aka: null,
      address_line1: '12 SEA STREET',
      address_line2: 'N/A',
      city: 'ROCKPORT',
      state: 'MA',
      state_name: 'Maine',
      zip: '04856',
      pub78_city: 'Rockport',
      pub78_state: 'MA',
      bmf_city: 'ROCKPORT',
      bmf_state: 'MA',
      bmf_street_address: '12 SEA STREET',
    },
  ),

  // Nothing adverse, but every source is well out of date. A workflow with a
  // re-review rule should notice this even though the findings look clean.
  [FIXTURE_EINS.staleData]: publicCharity(
    FIXTURE_EINS.staleData,
    'Long Quiet Example Foundation',
    {
      organization_info_last_modified: apiDate(700),
      most_recent_pub78: apiDate(640),
      most_recent_bmf: apiDate(610),
      ofac_list_published_date: apiDate(580),
      aroe_list_published_date: apiDate(560),
    },
  ),

  [FIXTURE_EINS.revoked]: publicCharity(
    FIXTURE_EINS.revoked,
    'Lapsed Filings Example Society',
    {
      organization_name_aka: null,
      pub78_verified: false,
      pub78_indicator: null,
      organization_types: null,
      bmf_status: false,
      bmf_deductability_text: 'Contributions are not deductible',
      subsection_description: '501(c)(3) Public Charity',
      exempt_status_code: '25',
      revocation_code: '01',
      revocation_date: apiDate(1_260),
      reinstatement_date: null,
    },
  ),

  [FIXTURE_EINS.reinstated]: publicCharity(
    FIXTURE_EINS.reinstated,
    'Second Chance Example Alliance',
    {
      organization_name_aka: 'SECOND CHANCE E.A',
      revocation_code: '01',
      revocation_date: apiDate(1_260),
      reinstatement_date: apiDate(520),
    },
  ),

  [FIXTURE_EINS.ofacMatch]: publicCharity(
    FIXTURE_EINS.ofacMatch,
    'Overseas Relief Example Fund',
    {
      organization_name_aka: 'OVERSEAS RELIEF E.F',
      ofac_status: OFAC_POSSIBLE_MATCH,
    },
  ),

  // The API returned nothing for OFAC. Absent is not the same as "no match".
  [FIXTURE_EINS.ofacUnavailable]: publicCharity(
    FIXTURE_EINS.ofacUnavailable,
    'Riverbend Example Coalition',
    {
      ofac_status: null,
      ofac_list_published_date: null,
    },
  ),

  // BMF says exempt, Publication 78 does not list the organization, and the API
  // flags the disagreement rather than picking a winner.
  [FIXTURE_EINS.conflicted]: publicCharity(
    FIXTURE_EINS.conflicted,
    'Crosscheck Example Institute',
    {
      organization_name: 'CROSSCHECK EXAMPLE INSTITUTE',
      pub78_organization_name: null,
      pub78_ein: null,
      pub78_verified: false,
      pub78_city: null,
      pub78_state: null,
      pub78_indicator: null,
      organization_types: null,
      most_recent_pub78: apiDate(26),
      bmf_organization_name: 'CROSSCHECK EXAMPLE INST',
      bmf_status: true,
      irs_bmf_pub78_conflict: true,
    },
  ),

  // A response from a newer API version: fields this SDK has never heard of, and
  // an enum value outside the documented set.
  [FIXTURE_EINS.futureFields]: publicCharity(
    FIXTURE_EINS.futureFields,
    'Forward Compatible Example Trust',
    {
      foundation_type_code: 'zz',
      foundation_type_description: 'A classification added after this SDK was published',
      organization_types: [
        {
          ...DEDUCTIBILITY_PUBLIC_CHARITY,
          deductibility_status_description: 'XX',
          future_deductibility_note: 'An unknown member of a known object',
        },
      ],
      state_charity_registration_status: 'ACTIVE',
      watchlist_screening: {
        provider: 'example',
        matches: 0,
        list_published_date: apiDate(5),
      },
    },
  ),
};

/**
 * Every field this package predicts on an organization.
 *
 * Read from `src/response-contract.json` rather than from a fixture, so that
 * what the SDK claims to know is stated in one place. A fixture is an example of
 * a record; the contract is the promise, and the promise is what drift is
 * measured against. See `ex-25`: a field outside this set is newer than this
 * SDK, which is not an error, but is worth knowing about.
 */
export const KNOWN_NONPROFIT_FIELDS = new Set(
  Object.keys(
    JSON.parse(readFileSync(fileURLToPath(new URL('../src/response-contract.json', import.meta.url)), 'utf8'))
      .nonprofit,
  ),
);

/** True when the mock server has a record for this EIN. */
export function hasFixture(ein) {
  return Object.hasOwn(FIXTURE_ORGANIZATIONS, ein);
}

/** A defensive copy, so an example mutating a record cannot affect later calls. */
export function fixtureOrganization(ein) {
  return structuredClone(FIXTURE_ORGANIZATIONS[ein]);
}
