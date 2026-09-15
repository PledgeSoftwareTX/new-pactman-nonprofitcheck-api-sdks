/**
 * The records the examples run against.
 *
 * Scenarios like a revoked exemption, an OFAC match, a cross-source conflict or
 * a field newer than the SDK cannot be summoned on demand from production. They
 * are declared here once, so that an example can demonstrate the handling and
 * {@link ExampleApiMock} can serve the record.
 *
 * Field names and values mirror the shapes the Pactman API reference documents.
 * The EINs are illustrative; they are not real organizations.
 *
 * This is a port of the Node SDK's `scripts/fixtures.mjs`, which remains the
 * source of truth for these records.
 */
@IsTest
public class ExampleFixtures {
    // The two OFAC sentences the API returns. It reports prose, not a boolean.

    /** The sentence the API returns when an organization is not on the SDN list. */
    public static final String OFAC_NO_MATCH =
        'This organization was NOT included in the Office of Foreign Assets Control ' +
        'Specially Designated Nationals (SDN) list.';

    /** The sentence the API returns when it found a close match. */
    public static final String OFAC_POSSIBLE_MATCH =
        'This organization may be included in the Office of Foreign Assets Control ' +
        'Specially Designated Nationals(SDN) list. ' +
        'A close match was found with the Special Designated National with UID: 41234';

    // EINs the fixture records are filed under, so that no example hard-codes a
    // bare number.

    /** A 501(c)(3) public charity with every source returned and nothing adverse. */
    public static final String PUBLIC_CHARITY = '411787097';

    /** A second clean organization, for the bulk examples. */
    public static final String PUBLIC_CHARITY_SECOND = '996589560';

    /** A 501(c)(3) private foundation — different foundation and filing codes. */
    public static final String PRIVATE_FOUNDATION = '042103594';

    /** Most optional identity fields returned as null, and no OFAC field at all. */
    public static final String SPARSE_IDENTITY = '060646700';

    /** Address fields that are all present and disagree with each other. */
    public static final String INCONSISTENT_ADDRESS = '311580204';

    /** Every source date well in the past. Nothing adverse. */
    public static final String STALE_DATA = '362167048';

    /** Listed in the IRS Automatic Revocation of Exemption data, not reinstated. */
    public static final String REVOKED = '237112796';

    /** Revoked and later reinstated — both dates present. */
    public static final String REINSTATED = '133039601';

    /** A possible OFAC SDN match. */
    public static final String OFAC_MATCH = '954367818';

    /** OFAC screening returned as null. Absent is not "no match". */
    public static final String OFAC_UNAVAILABLE = '061553389';

    /** BMF and Publication 78 disagree; `irs_bmf_pub78_conflict` is true. */
    public static final String CONFLICTED = '521693387';

    /** Fields and an enum value this SDK version does not know about. */
    public static final String FUTURE_FIELDS = '237324370';

    /** Production's shape plus the source fields only newer deployments return. */
    public static final String PENDING_SOURCE_FIELDS = '046001341';

    /** Well-formed, but no record exists. */
    public static final String NO_RECORD = '999999999';

    // EINs the mock answers with a specific failure, for the error examples.

    /** Always answers HTTP 429 with `Retry-After: 1`. */
    public static final String CONTROL_RATE_LIMITED = '900000429';

    /** Produces no response twice, then succeeds. */
    public static final String CONTROL_TRANSIENT_FAILURE = '900000503';

    /** Produces a callout timeout. */
    public static final String CONTROL_SLOW = '900000408';

    /**
     * Formats a date the way the API does — `M/DD/YYYY h:mm:ss AM` — `daysAgo`
     * before now.
     *
     * Fixture dates are relative to today so that the freshness examples stay
     * meaningful however long after they were written they run.
     */
    public static String apiDate(Integer daysAgo) {
        return Datetime.now().addDays(-daysAgo).format('M/dd/yyyy h:mm:ss a');
    }

    /** Every record the mock can return, keyed by normalized EIN. */
    public static Map<String, Map<String, Object>> organizations() {
        Map<String, Map<String, Object>> records = new Map<String, Map<String, Object>>();

        records.put(
            PUBLIC_CHARITY,
            withOverrides(
                publicCharity(PUBLIC_CHARITY, 'Meals Today Example Nonprofit'),
                new Map<String, Object>{
                    'organization_name_aka' => 'MEALS TODAY E.N',
                    'pub78_organization_name' => 'Meals Today Example Nonprofit, Inc.'
                }
            )
        );

        records.put(
            PUBLIC_CHARITY_SECOND,
            withOverrides(
                publicCharity(PUBLIC_CHARITY_SECOND, 'Aborjaily Example Nonprofit'),
                new Map<String, Object>{
                    'organization_name_aka' => 'ABORJAILY E.N',
                    'city' => 'SPRINGFIELD',
                    'pub78_city' => 'Springfield',
                    'zip' => '01103-1420',
                    'address_line1' => '19 HAMPDEN ST',
                    'address_line2' => null
                }
            )
        );

        // A private foundation files a 990-PF, so it carries no general 990
        // filing requirement.
        records.put(
            PRIVATE_FOUNDATION,
            withOverrides(
                publicCharity(PRIVATE_FOUNDATION, 'Hartwell Family Example Foundation'),
                new Map<String, Object>{
                    'organization_name_aka' => null,
                    'filing_req_code' => '00',
                    'organization_types' => new List<Object>{ deductibilityPrivateFoundation() },
                    'subsection_description' => '501(c)(3) Private Foundation',
                    'foundation_code' => '04',
                    'foundation_code_description' => 'Private non-operating foundation',
                    'foundation_type_code' => 'pf',
                    'foundation_type_description' => 'Private non-operating foundation',
                    'ruling_month' => '11',
                    'ruling_year' => '1998'
                }
            )
        );

        // Optional identity fields the API had no value for, and no OFAC key at
        // all: the source was not reported, which is neither a null status nor
        // a no-match result.
        Map<String, Object> sparse = withOverrides(
            publicCharity(SPARSE_IDENTITY, 'Quiet Harbor Example Trust'),
            new Map<String, Object>{
                'organization_name_aka' => null,
                'address_line1' => 'PO BOX 118',
                'address_line2' => null,
                'city' => 'ROCKPORT',
                'state' => 'ME',
                'state_name' => null,
                'zip' => null,
                'pub78_city' => null,
                'pub78_state' => null,
                'group_exemption' => null,
                'ruling_month' => null,
                'ruling_year' => null
            }
        );
        sparse.remove('ofac_status');
        records.put(SPARSE_IDENTITY, sparse);

        // Every address component is present, and they contradict one another:
        // the state code says Massachusetts, the state name and the ZIP say
        // Maine, and address_line2 holds a placeholder.
        records.put(
            INCONSISTENT_ADDRESS,
            withOverrides(
                publicCharity(INCONSISTENT_ADDRESS, 'Harbor Light Example Alliance'),
                new Map<String, Object>{
                    'organization_name_aka' => null,
                    'address_line1' => '12 SEA STREET',
                    'address_line2' => 'N/A',
                    'city' => 'ROCKPORT',
                    'state' => 'MA',
                    'state_name' => 'Maine',
                    'zip' => '04856',
                    'pub78_city' => 'Rockport',
                    'pub78_state' => 'MA'
                }
            )
        );

        // Nothing adverse, but every source is well out of date.
        records.put(
            STALE_DATA,
            withOverrides(
                publicCharity(STALE_DATA, 'Long Quiet Example Foundation'),
                new Map<String, Object>{
                    'organization_info_last_modified' => apiDate(700),
                    'most_recent_pub78' => apiDate(640),
                    'most_recent_bmf' => apiDate(610)
                }
            )
        );

        records.put(
            REVOKED,
            withOverrides(
                publicCharity(REVOKED, 'Lapsed Filings Example Society'),
                new Map<String, Object>{
                    'organization_name_aka' => null,
                    'pub78_verified' => false,
                    'pub78_indicator' => null,
                    'organization_types' => null,
                    'bmf_status' => false,
                    'exempt_status_code' => '25',
                    'revocation_code' => '01',
                    'revocation_date' => apiDate(1260),
                    'reinstatement_date' => null
                }
            )
        );

        records.put(
            REINSTATED,
            withOverrides(
                publicCharity(REINSTATED, 'Second Chance Example Alliance'),
                new Map<String, Object>{
                    'organization_name_aka' => 'SECOND CHANCE E.A',
                    'revocation_code' => '01',
                    'revocation_date' => apiDate(1260),
                    'reinstatement_date' => apiDate(520)
                }
            )
        );

        records.put(
            OFAC_MATCH,
            withOverrides(
                publicCharity(OFAC_MATCH, 'Overseas Relief Example Fund'),
                new Map<String, Object>{
                    'organization_name_aka' => 'OVERSEAS RELIEF E.F',
                    'ofac_status' => OFAC_POSSIBLE_MATCH
                }
            )
        );

        // The API returned nothing for OFAC. Absent is not the same as "no match".
        records.put(
            OFAC_UNAVAILABLE,
            withOverrides(
                publicCharity(OFAC_UNAVAILABLE, 'Riverbend Example Coalition'),
                new Map<String, Object>{ 'ofac_status' => null }
            )
        );

        // BMF says exempt, Publication 78 does not list the organization, and
        // the API flags the disagreement rather than picking a winner.
        records.put(
            CONFLICTED,
            withOverrides(
                publicCharity(CONFLICTED, 'Crosscheck Example Institute'),
                new Map<String, Object>{
                    'pub78_organization_name' => null,
                    'pub78_ein' => null,
                    'pub78_verified' => false,
                    'pub78_city' => null,
                    'pub78_state' => null,
                    'pub78_indicator' => null,
                    'organization_types' => null,
                    'bmf_organization_name' => 'CROSSCHECK EXAMPLE INST',
                    'bmf_status' => true,
                    'irs_bmf_pub78_conflict' => true
                }
            )
        );

        // A response from a newer API version: fields this SDK has never heard
        // of, and an enum value outside the documented set.
        records.put(
            FUTURE_FIELDS,
            withOverrides(
                publicCharity(FUTURE_FIELDS, 'Forward Compatible Example Trust'),
                new Map<String, Object>{
                    'foundation_type_code' => 'zz',
                    'foundation_type_description' =>
                        'A classification added after this SDK was published',
                    'organization_types' => new List<Object>{
                        withOverrides(
                            deductibilityPublicCharity(),
                            new Map<String, Object>{
                                'deductibility_status_description' => 'XX',
                                'future_deductibility_note' =>
                                    'An unknown member of a known object'
                            }
                        )
                    },
                    'state_charity_registration_status' => 'ACTIVE',
                    'watchlist_screening' => new Map<String, Object>{
                        'provider' => 'example',
                        'matches' => 0,
                        'list_published_date' => apiDate(5)
                    }
                }
            )
        );

        // A deployment running ahead of production: the ten source fields that
        // are built but not yet released there. The SDK does not declare them,
        // so they exercise the path that keeps undeclared fields readable.
        records.put(
            PENDING_SOURCE_FIELDS,
            withOverrides(
                publicCharity(PENDING_SOURCE_FIELDS, 'Ahead Of Production Example Fund'),
                new Map<String, Object>{
                    'organization_name_aka' => null,
                    'pub78_source_org_type_1' => 'PC',
                    'pub78_source_org_type_2' => null,
                    'pub78_source_org_type_3' => null,
                    'bmf_city' => 'WESTFIELD',
                    'bmf_state' => 'MA',
                    'bmf_street_address' => '50 LOWELL AVE APT 3B',
                    'bmf_source_pf_filing_req_cd' => '0',
                    'bmf_deductability_text' => 'Contributions are deductible',
                    'ofac_list_published_date' => apiDate(5),
                    'aroe_list_published_date' => apiDate(12)
                }
            )
        );

        return records;
    }

    /** A complete, unremarkable public charity. Scenarios override from here. */
    private static Map<String, Object> publicCharity(String ein, String name) {
        return new Map<String, Object>{
            'pactman_org_url' => 'https://pactman.org/profile/nonprofit/' +
                slug(name) + '-' + ein.right(4),
            'organization_info_last_modified' => apiDate(40),
            'ein' => ein,
            'organization_name' => name.toUpperCase(),
            'organization_name_aka' => null,
            'address_line1' => '50 LOWELL AVE',
            'address_line2' => 'APT 3B',
            'city' => 'WESTFIELD',
            'state' => 'MA',
            'state_name' => 'Massachusetts',
            'zip' => '01085-2643',
            'filing_req_code' => '01',
            'pub78_church_message' => null,
            'pub78_organization_name' => name,
            'pub78_ein' => ein,
            'pub78_verified' => true,
            'pub78_city' => 'Westfield',
            'pub78_state' => 'MA',
            'pub78_indicator' => '0',
            'organization_types' => new List<Object>{ deductibilityPublicCharity() },
            'most_recent_pub78' => apiDate(26),
            'bmf_church_message' => null,
            'bmf_organization_name' => name.toUpperCase(),
            'bmf_ein' => ein,
            'bmf_status' => true,
            'bmf_subsection' => '03',
            'most_recent_bmf' => apiDate(20),
            'subsection_description' => '501(c)(3) Public Charity',
            'foundation_code' => '10',
            'foundation_code_description' =>
                'Public charity described in section 509(a)(1) or (2)',
            'foundation_type_code' => 'pc',
            'foundation_type_description' =>
                'Public charity described in section 509(a)(1) or (2)',
            'foundation_509a_status' => 'N/A',
            'ruling_month' => '07',
            'ruling_year' => '2024',
            'group_exemption' => '0000',
            'exempt_status_code' => '01',
            'ofac_status' => OFAC_NO_MATCH,
            'revocation_code' => null,
            'revocation_date' => null,
            'reinstatement_date' => null,
            'irs_bmf_pub78_conflict' => false,
            'report_date' => apiDate(0)
        };
    }

    private static Map<String, Object> deductibilityPublicCharity() {
        return new Map<String, Object>{
            'organization_type' =>
                'Deductions for donations to public charities are generally limited to 50 percent ' +
                'of adjusted gross income (AGI). This limit increases to 60% of AGI for cash ' +
                'donations. For Non-Cash assets held for more than one year, the limit is 30% of AGI.',
            'deductibility_limitation' => '50%',
            'deductibility_status_description' => 'PC'
        };
    }

    private static Map<String, Object> deductibilityPrivateFoundation() {
        return new Map<String, Object>{
            'organization_type' =>
                'Deductions for donations to private foundations are generally limited to 30 percent ' +
                'of adjusted gross income (AGI). For Non-Cash assets held for more than one year, ' +
                'the limit is 20% of AGI.',
            'deductibility_limitation' => '30%',
            'deductibility_status_description' => 'PF'
        };
    }

    /**
     * Applies overrides to a copy of a record.
     *
     * A key set to `null` here is a field the API returned as null. Removing a
     * field outright — see `sparse` above — is how a record says "the API
     * returned no such field", which is a different fact.
     */
    private static Map<String, Object> withOverrides(
        Map<String, Object> record,
        Map<String, Object> overrides
    ) {
        Map<String, Object> result = record.clone();

        for (String key : overrides.keySet()) {
            result.put(key, overrides.get(key));
        }

        return result;
    }

    private static String slug(String name) {
        String lowered = name.toLowerCase();
        String cleaned = '';

        for (Integer index = 0; index < lowered.length(); index++) {
            String character = lowered.substring(index, index + 1);
            cleaned += character.isAlphanumeric() ? character : '-';
        }

        while (cleaned.contains('--')) {
            cleaned = cleaned.replace('--', '-');
        }

        return cleaned.removeStart('-').removeEnd('-');
    }
}
