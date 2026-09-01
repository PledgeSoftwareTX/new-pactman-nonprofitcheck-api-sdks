/** IRS Business Master File findings. Built by {@link Sources.getBmf}. */
global class BmfSource extends DataObject {
    global BmfSource(Map<String, Object> fields) {
        super(fields);
    }

    global Boolean status {
        get { return getBoolean('status'); }
    }

    global String organization_name {
        get { return getString('organization_name'); }
    }

    global String ein {
        get { return getString('ein'); }
    }

    global String church_message {
        get { return getString('church_message'); }
    }

    global String subsection {
        get { return getString('subsection'); }
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

    global String filing_req_code {
        get { return getString('filing_req_code'); }
    }

    global String most_recent {
        get { return getString('most_recent'); }
    }

}
