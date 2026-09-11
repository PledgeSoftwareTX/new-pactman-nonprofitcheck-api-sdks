package org.pactman.nonprofitcheckplus.models;

import java.util.List;
import java.util.Map;

/**
 * A nonprofit record as returned by the US nonprofit check endpoints.
 *
 * <p>Source-specific findings are flat on this object, prefixed by source
 * ({@code pub78_*}, {@code bmf_*}, {@code ofac_*}, and the revocation fields for
 * the IRS Automatic Revocation of Exemption list). See
 * {@link org.pactman.nonprofitcheckplus.Sources} for grouped views.
 *
 * <p>Every field is optional: the API omits fields it has no data for. Reading
 * one it did not return yields {@code null}; ask {@link DataObject#has(String)}
 * to tell the two apart. Fields introduced by a newer API version than this SDK
 * knows about are readable through {@link DataObject#get(String)}.
 *
 * <p>Declared here is what the production API returns. Some deployments serve
 * additional source fields — the BMF address ({@code bmf_city},
 * {@code bmf_state}, {@code bmf_street_address}),
 * {@code bmf_source_pf_filing_req_cd}, {@code bmf_deductability_text},
 * {@code pub78_source_org_type_1..3}, {@code ofac_list_published_date} and
 * {@code aroe_list_published_date}. They are not declared because production
 * does not return them; when it does, they stay readable through
 * {@link DataObject#get(String)}, and this package will declare them in a
 * release of its own.
 */
public final class Nonprofit extends DataObject {

    /**
     * Initializes the record from a decoded JSON object.
     *
     * @param fields the organization as the API sent it.
     */
    public Nonprofit(Map<String, Object> fields) {
        super(fields);
    }

    /**
     * Public Pactman profile URL for the organization.
     *
     * @return the URL, or {@code null} when the API returned none.
     */
    public String getPactmanOrgUrl() {
        return getString("pactman_org_url");
    }

    /**
     * When Pactman last modified this organization's record.
     *
     * @return the timestamp as the API formats it, or {@code null}.
     */
    public String getOrganizationInfoLastModified() {
        return getString("organization_info_last_modified");
    }

    /**
     * The organization's EIN, as nine digits.
     *
     * @return the EIN, or {@code null} when the API returned none.
     */
    public String getEin() {
        return getString("ein");
    }

    /**
     * The organization's legal name.
     *
     * @return the name, or {@code null} when the API returned none.
     */
    public String getOrganizationName() {
        return getString("organization_name");
    }

    /**
     * The organization's "also known as" name.
     *
     * @return the alternate name, or {@code null} when the API returned none.
     */
    public String getOrganizationNameAka() {
        return getString("organization_name_aka");
    }

    /**
     * First line of the organization's address.
     *
     * @return the line, or {@code null} when the API returned none.
     */
    public String getAddressLine1() {
        return getString("address_line1");
    }

    /**
     * Second line of the organization's address.
     *
     * @return the line, or {@code null} when the API returned none.
     */
    public String getAddressLine2() {
        return getString("address_line2");
    }

    /**
     * The organization's city.
     *
     * @return the city, or {@code null} when the API returned none.
     */
    public String getCity() {
        return getString("city");
    }

    /**
     * The organization's two-letter state code.
     *
     * @return the state code, or {@code null} when the API returned none.
     */
    public String getState() {
        return getString("state");
    }

    /**
     * The organization's state, spelled out.
     *
     * @return the state name, or {@code null} when the API returned none.
     */
    public String getStateName() {
        return getString("state_name");
    }

    /**
     * The organization's ZIP code.
     *
     * @return the ZIP, or {@code null} when the API returned none.
     */
    public String getZip() {
        return getString("zip");
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
     * The Publication 78 note for organizations the IRS treats as churches.
     *
     * @return the note, or {@code null} when the API returned none.
     */
    public String getPub78ChurchMessage() {
        return getString("pub78_church_message");
    }

    /**
     * The organization's name as Publication 78 records it.
     *
     * @return the name, or {@code null} when the API returned none.
     */
    public String getPub78OrganizationName() {
        return getString("pub78_organization_name");
    }

    /**
     * The EIN as Publication 78 records it.
     *
     * @return the EIN, or {@code null} when the API returned none.
     */
    public String getPub78Ein() {
        return getString("pub78_ein");
    }

    /**
     * Whether the organization appears in Publication 78.
     *
     * @return the flag, or {@code null} when the API returned none.
     */
    public Boolean getPub78Verified() {
        return getBoolean("pub78_verified");
    }

    /**
     * The city as Publication 78 records it.
     *
     * @return the city, or {@code null} when the API returned none.
     */
    public String getPub78City() {
        return getString("pub78_city");
    }

    /**
     * The state as Publication 78 records it.
     *
     * @return the state, or {@code null} when the API returned none.
     */
    public String getPub78State() {
        return getString("pub78_state");
    }

    /**
     * The Publication 78 deductibility indicator.
     *
     * @return the indicator, or {@code null} when the API returned none.
     */
    public String getPub78Indicator() {
        return getString("pub78_indicator");
    }

    /**
     * The Publication 78 deductibility entries, as the API sent them.
     *
     * <p>Empty when the field was absent or null, so it is always safe to
     * iterate; ask {@code has("organization_types")} when the difference matters.
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
    public String getMostRecentPub78() {
        return getString("most_recent_pub78");
    }

    /**
     * The Business Master File note for organizations the IRS treats as churches.
     *
     * @return the note, or {@code null} when the API returned none.
     */
    public String getBmfChurchMessage() {
        return getString("bmf_church_message");
    }

    /**
     * The organization's name as the Business Master File records it.
     *
     * @return the name, or {@code null} when the API returned none.
     */
    public String getBmfOrganizationName() {
        return getString("bmf_organization_name");
    }

    /**
     * The EIN as the Business Master File records it.
     *
     * @return the EIN, or {@code null} when the API returned none.
     */
    public String getBmfEin() {
        return getString("bmf_ein");
    }

    /**
     * Whether the organization appears in the Business Master File.
     *
     * @return the flag, or {@code null} when the API returned none.
     */
    public Boolean getBmfStatus() {
        return getBoolean("bmf_status");
    }

    /**
     * The IRC subsection under which the organization is exempt.
     *
     * @return the subsection, or {@code null} when the API returned none.
     */
    public String getBmfSubsection() {
        return getString("bmf_subsection");
    }

    /**
     * The date of the most recent Business Master File extract behind this record.
     *
     * @return the date as the API formats it, or {@code null}.
     */
    public String getMostRecentBmf() {
        return getString("most_recent_bmf");
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
     * The OFAC Specially Designated Nationals finding.
     *
     * <p>This is prose, not a flag. The API does not currently return a boolean
     * match indicator, and this SDK does not invent one by matching on the
     * wording. Read it, or present it to a reviewer.
     *
     * @return the finding, or {@code null} when the API returned none.
     */
    public String getOfacStatus() {
        return getString("ofac_status");
    }

    /**
     * The IRS automatic revocation code, when the exemption was revoked.
     *
     * @return the code, or {@code null} when the API returned none.
     */
    public String getRevocationCode() {
        return getString("revocation_code");
    }

    /**
     * The date the exemption was automatically revoked.
     *
     * @return the date as the API formats it, or {@code null}.
     */
    public String getRevocationDate() {
        return getString("revocation_date");
    }

    /**
     * The date the exemption was reinstated, when it was.
     *
     * @return the date as the API formats it, or {@code null}.
     */
    public String getReinstatementDate() {
        return getString("reinstatement_date");
    }

    /**
     * True when the IRS Business Master File and Publication 78 records disagree.
     *
     * @return the flag, or {@code null} when the API returned none.
     */
    public Boolean getIrsBmfPub78Conflict() {
        return getBoolean("irs_bmf_pub78_conflict");
    }

    /**
     * The date Pactman compiled this report.
     *
     * @return the date as the API formats it, or {@code null}.
     */
    public String getReportDate() {
        return getString("report_date");
    }
}
