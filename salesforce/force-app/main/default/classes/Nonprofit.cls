/**
 * A nonprofit record as returned by the US nonprofit check endpoints.
 *
 * Source-specific findings are flat on this object, prefixed by source
 * (`pub78_*`, `bmf_*`, `ofac_*`, and the revocation fields for the IRS
 * Automatic Revocation of Exemption list). See {@link Sources} for grouped
 * views.
 *
 * Every field is optional: the API omits fields it has no data for, and a
 * production deployment may omit fields this contract lists. Reading one the
 * API did not return yields `null`; ask {@link DataObject.has} to tell the two
 * apart. Fields introduced by a newer API version than this SDK knows about are
 * readable through {@link DataObject.get}.
 *
 * Declared here is what the production API returns. Some deployments serve
 * additional source fields — the BMF address (`bmf_city`, `bmf_state`,
 * `bmf_street_address`), `bmf_source_pf_filing_req_cd`, `bmf_deductability_text`,
 * `pub78_source_org_type_1..3`, `ofac_list_published_date` and
 * `aroe_list_published_date`. They are not declared because production does not
 * return them; when it does, they stay readable through {@link DataObject.get},
 * and this package will declare them in a release of its own.
 *
 * Accessors are `snake_case` to match the wire format and the other Pactman
 * SDKs exactly — see {@link DataObject} for why.
 */
global class Nonprofit extends DataObject {
    global Nonprofit(Map<String, Object> fields) {
        super(fields);
    }

    /** Public Pactman profile URL for the organization. */
    global String pactman_org_url {
        get { return getString('pactman_org_url'); }
    }

    global String organization_info_last_modified {
        get { return getString('organization_info_last_modified'); }
    }

    global String ein {
        get { return getString('ein'); }
    }

    global String organization_name {
        get { return getString('organization_name'); }
    }

    global String organization_name_aka {
        get { return getString('organization_name_aka'); }
    }

    global String address_line1 {
        get { return getString('address_line1'); }
    }

    global String address_line2 {
        get { return getString('address_line2'); }
    }

    global String city {
        get { return getString('city'); }
    }

    global String state {
        get { return getString('state'); }
    }

    global String state_name {
        get { return getString('state_name'); }
    }

    global String zip {
        get { return getString('zip'); }
    }

    global String filing_req_code {
        get { return getString('filing_req_code'); }
    }

    // IRS Publication 78

    global String pub78_church_message {
        get { return getString('pub78_church_message'); }
    }

    global String pub78_organization_name {
        get { return getString('pub78_organization_name'); }
    }

    global String pub78_ein {
        get { return getString('pub78_ein'); }
    }

    global String pub78_city {
        get { return getString('pub78_city'); }
    }

    global String pub78_state {
        get { return getString('pub78_state'); }
    }

    global String pub78_indicator {
        get { return getString('pub78_indicator'); }
    }

    global String most_recent_pub78 {
        get { return getString('most_recent_pub78'); }
    }

    global Boolean pub78_verified {
        get { return getBoolean('pub78_verified'); }
    }

    /**
     * Publication 78 deductibility entries.
     *
     * Never null — an absent field yields an empty list. Entries the API sent as
     * `null` are skipped rather than surfaced as null members.
     */
    global List<OrganizationType> organization_types {
        get {
            List<OrganizationType> result = new List<OrganizationType>();
            List<Object> raw = getList('organization_types');

            if (raw == null) {
                return result;
            }

            for (Object entry : raw) {
                if (entry instanceof Map<String, Object>) {
                    result.add(new OrganizationType((Map<String, Object>) entry));
                }
            }

            return result;
        }
    }

    // IRS Business Master File

    global String bmf_church_message {
        get { return getString('bmf_church_message'); }
    }

    global String bmf_organization_name {
        get { return getString('bmf_organization_name'); }
    }

    global String bmf_ein {
        get { return getString('bmf_ein'); }
    }

    global String bmf_subsection {
        get { return getString('bmf_subsection'); }
    }

    global String most_recent_bmf {
        get { return getString('most_recent_bmf'); }
    }

    global Boolean bmf_status {
        get { return getBoolean('bmf_status'); }
    }

    global String subsection_description {
        get { return getString('subsection_description'); }
    }

    global String foundation_code {
        get { return getString('foundation_code'); }
    }

    global String foundation_code_description {
        get { return getString('foundation_code_description'); }
    }

    global String foundation_type_code {
        get { return getString('foundation_type_code'); }
    }

    global String foundation_type_description {
        get { return getString('foundation_type_description'); }
    }

    global String foundation_509a_status {
        get { return getString('foundation_509a_status'); }
    }

    global String ruling_month {
        get { return getString('ruling_month'); }
    }

    global String ruling_year {
        get { return getString('ruling_year'); }
    }

    global String group_exemption {
        get { return getString('group_exemption'); }
    }

    global String exempt_status_code {
        get { return getString('exempt_status_code'); }
    }

    /**
     * OFAC Specially Designated Nationals finding.
     *
     * The API returns a sentence, not a flag — do not pattern-match it to derive
     * a boolean. Read it, or present it to a reviewer.
     */
    global String ofac_status {
        get { return getString('ofac_status'); }
    }

    // IRS Automatic Revocation of Exemption

    global String revocation_code {
        get { return getString('revocation_code'); }
    }

    global String revocation_date {
        get { return getString('revocation_date'); }
    }

    global String reinstatement_date {
        get { return getString('reinstatement_date'); }
    }

    /** True when the IRS BMF and Publication 78 records disagree. */
    global Boolean irs_bmf_pub78_conflict {
        get { return getBoolean('irs_bmf_pub78_conflict'); }
    }

    global String report_date {
        get { return getString('report_date'); }
    }

}
