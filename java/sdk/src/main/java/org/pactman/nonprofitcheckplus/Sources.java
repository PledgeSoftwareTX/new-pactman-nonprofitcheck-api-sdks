package org.pactman.nonprofitcheckplus;

import java.util.LinkedHashMap;
import java.util.Map;
import org.pactman.nonprofitcheckplus.models.AroeSource;
import org.pactman.nonprofitcheckplus.models.BmfSource;
import org.pactman.nonprofitcheckplus.models.Nonprofit;
import org.pactman.nonprofitcheckplus.models.OfacSource;
import org.pactman.nonprofitcheckplus.models.Pub78Source;

/**
 * Grouped views over the source-specific findings on a {@link Nonprofit}.
 *
 * <p>These are projections, not derivations: every key is copied 1:1 from a
 * field the API returned. Nothing here computes an "approved", "eligible" or
 * "safe" verdict, and nothing infers a value from another field.
 *
 * <p>Each accessor returns {@code null} when the API returned no data at all for
 * that source. That keeps "the source was not returned" distinguishable from an
 * explicit negative such as {@code pub78_verified: false} or a null field.
 */
public final class Sources {

    private static final String[][] PUB78_FIELDS = {
        {"verified", "pub78_verified"},
        {"organization_name", "pub78_organization_name"},
        {"ein", "pub78_ein"},
        {"city", "pub78_city"},
        {"state", "pub78_state"},
        {"indicator", "pub78_indicator"},
        {"church_message", "pub78_church_message"},
        {"organization_types", "organization_types"},
        {"most_recent", "most_recent_pub78"},
    };

    private static final String[][] BMF_FIELDS = {
        {"status", "bmf_status"},
        {"organization_name", "bmf_organization_name"},
        {"ein", "bmf_ein"},
        {"church_message", "bmf_church_message"},
        {"subsection", "bmf_subsection"},
        {"subsection_description", "subsection_description"},
        {"foundation_code", "foundation_code"},
        {"foundation_code_description", "foundation_code_description"},
        {"foundation_type_code", "foundation_type_code"},
        {"foundation_type_description", "foundation_type_description"},
        {"foundation_509a_status", "foundation_509a_status"},
        {"ruling_month", "ruling_month"},
        {"ruling_year", "ruling_year"},
        {"group_exemption", "group_exemption"},
        {"exempt_status_code", "exempt_status_code"},
        {"filing_req_code", "filing_req_code"},
        {"most_recent", "most_recent_bmf"},
    };

    private static final String[][] AROE_FIELDS = {
        {"revocation_code", "revocation_code"},
        {"revocation_date", "revocation_date"},
        {"reinstatement_date", "reinstatement_date"},
    };

    private static final String[][] OFAC_FIELDS = {
        {"status", "ofac_status"},
    };

    private Sources() {
    }

    /**
     * Publication 78 findings.
     *
     * @param nonprofit the organization to project.
     * @return the grouped findings, or {@code null} if the API returned none.
     */
    public static Pub78Source pub78(Nonprofit nonprofit) {
        Map<String, Object> fields = project(nonprofit, PUB78_FIELDS);

        return fields == null ? null : new Pub78Source(fields);
    }

    /**
     * Business Master File findings.
     *
     * @param nonprofit the organization to project.
     * @return the grouped findings, or {@code null} if the API returned none.
     */
    public static BmfSource bmf(Nonprofit nonprofit) {
        Map<String, Object> fields = project(nonprofit, BMF_FIELDS);

        return fields == null ? null : new BmfSource(fields);
    }

    /**
     * Automatic Revocation of Exemption findings.
     *
     * @param nonprofit the organization to project.
     * @return the grouped findings, or {@code null} if the API returned none.
     */
    public static AroeSource aroe(Nonprofit nonprofit) {
        Map<String, Object> fields = project(nonprofit, AROE_FIELDS);

        return fields == null ? null : new AroeSource(fields);
    }

    /**
     * OFAC findings.
     *
     * @param nonprofit the organization to project.
     * @return the grouped findings, or {@code null} if the API returned none.
     */
    public static OfacSource ofac(Nonprofit nonprofit) {
        Map<String, Object> fields = project(nonprofit, OFAC_FIELDS);

        return fields == null ? null : new OfacSource(fields);
    }

    /**
     * Copies the mapped fields into a new map, preserving null and false.
     *
     * <p>Returns {@code null} only when every mapped field is absent from the
     * response, which is how "this source was not returned" is represented.
     */
    private static Map<String, Object> project(Nonprofit nonprofit, String[][] mapping) {
        if (nonprofit == null) {
            return null;
        }

        Map<String, Object> projected = new LinkedHashMap<>();

        for (String[] pair : mapping) {
            if (nonprofit.has(pair[1])) {
                projected.put(pair[0], nonprofit.get(pair[1]));
            }
        }

        return projected.isEmpty() ? null : projected;
    }
}
