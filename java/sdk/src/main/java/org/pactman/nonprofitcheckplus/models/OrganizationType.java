package org.pactman.nonprofitcheckplus.models;

import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.Map;

/** A deductibility entry from IRS Publication 78. */
public final class OrganizationType extends DataObject {

    /**
     * Initializes the entry from a decoded JSON object.
     *
     * @param fields the entry as the API sent it.
     */
    public OrganizationType(Map<String, Object> fields) {
        super(fields);
    }

    /**
     * Reads a decoded {@code organization_types} value as a list of entries.
     *
     * <p>Returns an empty list when the value is absent, JSON null, or not an
     * array, so it is always safe to iterate.
     *
     * <p>The API can also send a null inside the list, for a Publication 78 row
     * it cannot resolve. Those are dropped rather than handed on, so every entry
     * this returns is a real object and the positions are renumbered from zero —
     * read {@code get("organization_types")} when the gaps themselves matter.
     *
     * @param value the decoded field value.
     * @return the entries the API sent.
     */
    public static List<OrganizationType> listFrom(Object value) {
        if (!(value instanceof List)) {
            return Collections.emptyList();
        }

        List<?> raw = (List<?>) value;
        List<OrganizationType> entries = new ArrayList<>(raw.size());

        for (Object entry : raw) {
            if (entry instanceof Map) {
                entries.add(new OrganizationType(asFields(entry)));
            }
        }

        return Collections.unmodifiableList(entries);
    }

    /**
     * The deductibility text for this entry.
     *
     * @return the text, or {@code null} when the API returned none.
     */
    public String getOrganizationType() {
        return getString("organization_type");
    }

    /**
     * The deductibility limitation, such as {@code 50%}.
     *
     * @return the limitation, or {@code null} when the API returned none.
     */
    public String getDeductibilityLimitation() {
        return getString("deductibility_limitation");
    }

    /**
     * The deductibility status code, such as {@code PC}.
     *
     * @return the status description, or {@code null} when the API returned none.
     */
    public String getDeductibilityStatusDescription() {
        return getString("deductibility_status_description");
    }
}
