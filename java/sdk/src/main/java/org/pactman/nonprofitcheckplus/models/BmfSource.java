package org.pactman.nonprofitcheckplus.models;

import java.util.Map;

/** IRS Business Master File findings. */
public final class BmfSource extends SourceView {

    /**
     * Initializes the view over the projected fields.
     *
     * @param fields the fields copied from the organization.
     */
    public BmfSource(Map<String, Object> fields) {
        super(fields);
    }

    /**
     * Whether the organization appears in the Business Master File.
     *
     * @return the flag, or {@code null} when the API returned none.
     */
    public Boolean getStatus() {
        return getBoolean("status");
    }

    /**
     * The organization's name as the Business Master File records it.
     *
     * @return the name, or {@code null} when the API returned none.
     */
    public String getOrganizationName() {
        return getString("organization_name");
    }

    /**
     * The EIN as the Business Master File records it.
     *
     * @return the EIN, or {@code null} when the API returned none.
     */
    public String getEin() {
        return getString("ein");
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
     * The IRC subsection under which the organization is exempt.
     *
     * @return the subsection, or {@code null} when the API returned none.
     */
    public String getSubsection() {
        return getString("subsection");
    }

    /**
     * The subsection, spelled out.
     *
     * @return the description, or {@code null} when the API returned none.
     */
    public String getSubsectionDescription() {
        return getString("subsection_description");
    }

    /**
     * The IRS foundation code.
     *
     * @return the code, or {@code null} when the API returned none.
     */
    public String getFoundationCode() {
        return getString("foundation_code");
    }

    /**
     * The foundation code, spelled out.
     *
     * @return the description, or {@code null} when the API returned none.
     */
    public String getFoundationCodeDescription() {
        return getString("foundation_code_description");
    }

    /**
     * The IRS foundation type code.
     *
     * @return the code, or {@code null} when the API returned none.
     */
    public String getFoundationTypeCode() {
        return getString("foundation_type_code");
    }

    /**
     * The foundation type, spelled out.
     *
     * @return the description, or {@code null} when the API returned none.
     */
    public String getFoundationTypeDescription() {
        return getString("foundation_type_description");
    }

    /**
     * The organization's 509(a) status.
     *
     * @return the status, or {@code null} when the API returned none.
     */
    public String getFoundation509aStatus() {
        return getString("foundation_509a_status");
    }

    /**
     * The month of the IRS ruling.
     *
     * @return the month, or {@code null} when the API returned none.
     */
    public String getRulingMonth() {
        return getString("ruling_month");
    }

    /**
     * The year of the IRS ruling.
     *
     * @return the year, or {@code null} when the API returned none.
     */
    public String getRulingYear() {
        return getString("ruling_year");
    }

    /**
     * The group exemption number, when the organization holds one.
     *
     * @return the number, or {@code null} when the API returned none.
     */
    public String getGroupExemption() {
        return getString("group_exemption");
    }

    /**
     * The IRS exempt status code.
     *
     * @return the code, or {@code null} when the API returned none.
     */
    public String getExemptStatusCode() {
        return getString("exempt_status_code");
    }

    /**
     * The IRS filing requirement code.
     *
     * @return the code, or {@code null} when the API returned none.
     */
    public String getFilingReqCode() {
        return getString("filing_req_code");
    }

    /**
     * The date of the most recent Business Master File extract behind this record.
     *
     * @return the date as the API formats it, or {@code null}.
     */
    public String getMostRecent() {
        return getString("most_recent");
    }
}
