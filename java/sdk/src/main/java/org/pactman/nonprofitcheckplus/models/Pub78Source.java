package org.pactman.nonprofitcheckplus.models;

import java.util.List;
import java.util.Map;

/** IRS Publication 78 findings. */
public final class Pub78Source extends SourceView {

    /**
     * Initializes the view over the projected fields.
     *
     * @param fields the fields copied from the organization.
     */
    public Pub78Source(Map<String, Object> fields) {
        super(fields);
    }

    /**
     * Whether the organization appears in Publication 78.
     *
     * @return the flag, or {@code null} when the API returned none.
     */
    public Boolean getVerified() {
        return getBoolean("verified");
    }

    /**
     * The organization's name as Publication 78 records it.
     *
     * @return the name, or {@code null} when the API returned none.
     */
    public String getOrganizationName() {
        return getString("organization_name");
    }

    /**
     * The EIN as Publication 78 records it.
     *
     * @return the EIN, or {@code null} when the API returned none.
     */
    public String getEin() {
        return getString("ein");
    }

    /**
     * The city as Publication 78 records it.
     *
     * @return the city, or {@code null} when the API returned none.
     */
    public String getCity() {
        return getString("city");
    }

    /**
     * The state as Publication 78 records it.
     *
     * @return the state, or {@code null} when the API returned none.
     */
    public String getState() {
        return getString("state");
    }

    /**
     * The Publication 78 deductibility indicator.
     *
     * @return the indicator, or {@code null} when the API returned none.
     */
    public String getIndicator() {
        return getString("indicator");
    }

    /**
     * The note for organizations the IRS treats as churches.
     *
     * @return the note, or {@code null} when the API returned none.
     */
    public String getChurchMessage() {
        return getString("church_message");
    }

    /**
     * The Publication 78 deductibility entries, as the API sent them.
     *
     * <p>Empty when the API sent none, so it is always safe to iterate; ask
     * {@code has("organization_types")} when the difference matters.
     *
     * @return the entries.
     */
    public List<OrganizationType> getOrganizationTypes() {
        return OrganizationType.listFrom(get("organization_types"));
    }

    /**
     * The date of the most recent Publication 78 extract behind this record.
     *
     * @return the date as the API formats it, or {@code null}.
     */
    public String getMostRecent() {
        return getString("most_recent");
    }
}
