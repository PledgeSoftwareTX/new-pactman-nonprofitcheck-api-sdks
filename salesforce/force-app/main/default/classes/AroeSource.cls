/** IRS Automatic Revocation of Exemption findings. Built by {@link Sources.getAroe}. */
global class AroeSource extends DataObject {
    global AroeSource(Map<String, Object> fields) {
        super(fields);
    }

    global String revocation_code {
        get { return getString('revocation_code'); }
    }

    global String revocation_date {
        get { return getString('revocation_date'); }
    }

    global String reinstatement_date {
        get { return getString('reinstatement_date'); }
    }

    global String list_published_date {
        get { return getString('list_published_date'); }
    }

}
