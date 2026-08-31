/** OFAC Specially Designated Nationals findings. Built by {@link Sources.getOfac}. */
global class OfacSource extends DataObject {
    global OfacSource(Map<String, Object> fields) {
        super(fields);
    }

    /**
     * The finding as the API phrases it.
     *
     * Prose, not a flag. The API does not return a boolean match indicator, and
     * this SDK does not invent one by matching on the wording.
     */
    global String status {
        get { return getString('status'); }
    }

    global String list_published_date {
        get { return getString('list_published_date'); }
    }

}
