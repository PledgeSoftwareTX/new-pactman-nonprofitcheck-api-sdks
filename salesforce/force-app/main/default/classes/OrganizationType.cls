/** A deductibility entry from IRS Publication 78. */
global class OrganizationType extends DataObject {
    global OrganizationType(Map<String, Object> fields) {
        super(fields);
    }

    global String organization_type {
        get { return getString('organization_type'); }
    }

    global String deductibility_limitation {
        get { return getString('deductibility_limitation'); }
    }

    global String deductibility_status_description {
        get { return getString('deductibility_status_description'); }
    }
}
