/** IRS Publication 78 findings. Built by {@link Sources.getPub78}. */
global class Pub78Source extends DataObject {
    global Pub78Source(Map<String, Object> fields) {
        super(fields);
    }

    global Boolean verified {
        get { return getBoolean('verified'); }
    }

    global String organization_name {
        get { return getString('organization_name'); }
    }

    global String ein {
        get { return getString('ein'); }
    }

    global String city {
        get { return getString('city'); }
    }

    global String state {
        get { return getString('state'); }
    }

    global String indicator {
        get { return getString('indicator'); }
    }

    global String church_message {
        get { return getString('church_message'); }
    }

    global String source_org_type_1 {
        get { return getString('source_org_type_1'); }
    }

    global String source_org_type_2 {
        get { return getString('source_org_type_2'); }
    }

    global String source_org_type_3 {
        get { return getString('source_org_type_3'); }
    }

    global String most_recent {
        get { return getString('most_recent'); }
    }

    /** Deductibility entries. Never null; an absent field yields an empty list. */
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
}
