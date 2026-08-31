/**
 * Grouped views over the source-specific findings on a {@link Nonprofit}.
 *
 * These are projections, not derivations: every key is copied 1:1 from a field
 * the API returned. Nothing here computes an "approved", "eligible" or "safe"
 * verdict, and nothing infers a value from another field.
 *
 * Each accessor returns `null` when the API returned no data at all for that
 * source. That keeps "the source was not returned" distinguishable from an
 * explicit negative such as `pub78_verified == false` or a `null` field.
 */
global class Sources {
    private static final Map<String, String> PUB78_FIELDS = new Map<String, String>{
        'verified' => 'pub78_verified',
        'organization_name' => 'pub78_organization_name',
        'ein' => 'pub78_ein',
        'city' => 'pub78_city',
        'state' => 'pub78_state',
        'indicator' => 'pub78_indicator',
        'church_message' => 'pub78_church_message',
        'source_org_type_1' => 'pub78_source_org_type_1',
        'source_org_type_2' => 'pub78_source_org_type_2',
        'source_org_type_3' => 'pub78_source_org_type_3',
        'organization_types' => 'organization_types',
        'most_recent' => 'most_recent_pub78'
    };

    private static final Map<String, String> BMF_FIELDS = new Map<String, String>{
        'status' => 'bmf_status',
        'organization_name' => 'bmf_organization_name',
        'ein' => 'bmf_ein',
        'city' => 'bmf_city',
        'state' => 'bmf_state',
        'street_address' => 'bmf_street_address',
        'church_message' => 'bmf_church_message',
        'subsection' => 'bmf_subsection',
        'subsection_description' => 'subsection_description',
        'foundation_code' => 'foundation_code',
        'foundation_code_description' => 'foundation_code_description',
        'foundation_type_code' => 'foundation_type_code',
        'foundation_type_description' => 'foundation_type_description',
        'foundation_509a_status' => 'foundation_509a_status',
        'ruling_month' => 'ruling_month',
        'ruling_year' => 'ruling_year',
        'group_exemption' => 'group_exemption',
        'exempt_status_code' => 'exempt_status_code',
        'filing_req_code' => 'filing_req_code',
        'pf_filing_req_cd' => 'bmf_source_pf_filing_req_cd',
        'deductability_text' => 'bmf_deductability_text',
        'most_recent' => 'most_recent_bmf'
    };

    private static final Map<String, String> AROE_FIELDS = new Map<String, String>{
        'revocation_code' => 'revocation_code',
        'revocation_date' => 'revocation_date',
        'reinstatement_date' => 'reinstatement_date',
        'list_published_date' => 'aroe_list_published_date'
    };

    private static final Map<String, String> OFAC_FIELDS = new Map<String, String>{
        'status' => 'ofac_status',
        'list_published_date' => 'ofac_list_published_date'
    };

    /** Publication 78 findings, or `null` if the API returned none. */
    global static Pub78Source getPub78(Nonprofit nonprofit) {
        Map<String, Object> projected = project(nonprofit, PUB78_FIELDS);
        return projected == null ? null : new Pub78Source(projected);
    }

    /** Business Master File findings, or `null` if the API returned none. */
    global static BmfSource getBmf(Nonprofit nonprofit) {
        Map<String, Object> projected = project(nonprofit, BMF_FIELDS);
        return projected == null ? null : new BmfSource(projected);
    }

    /** Automatic Revocation of Exemption findings, or `null` if the API returned none. */
    global static AroeSource getAroe(Nonprofit nonprofit) {
        Map<String, Object> projected = project(nonprofit, AROE_FIELDS);
        return projected == null ? null : new AroeSource(projected);
    }

    /** OFAC findings, or `null` if the API returned none. */
    global static OfacSource getOfac(Nonprofit nonprofit) {
        Map<String, Object> projected = project(nonprofit, OFAC_FIELDS);
        return projected == null ? null : new OfacSource(projected);
    }

    /**
     * Copies the mapped fields the API actually returned.
     *
     * Returns `null` when it returned none of them — the caller reads that as
     * "this source is absent", which is not the same as "this source said no".
     */
    private static Map<String, Object> project(Nonprofit nonprofit, Map<String, String> mapping) {
        if (nonprofit == null) {
            return null;
        }

        Map<String, Object> result = new Map<String, Object>();
        Boolean present = false;

        for (String target : mapping.keySet()) {
            String wireField = mapping.get(target);

            if (nonprofit.has(wireField)) {
                result.put(target, nonprofit.get(wireField));
                present = true;
            }
        }

        return present ? result : null;
    }
}
