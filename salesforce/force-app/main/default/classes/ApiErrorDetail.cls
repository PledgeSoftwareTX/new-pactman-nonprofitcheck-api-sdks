/**
 * One entry from the envelope's `errors` array.
 *
 * Present on successful responses too — a bulk request where some EINs were not
 * found returns HTTP 200 with entries here, which is where
 * {@link BulkCheckResult.notFoundEins} comes from.
 */
global class ApiErrorDetail extends DataObject {
    global ApiErrorDetail(Map<String, Object> fields) {
        super(fields);
    }

    /** The API resource the error came from. */
    global String resource {
        get { return getString('resource'); }
    }

    /** Human-readable explanation. */
    global String reason {
        get { return getString('reason'); }
    }

    /** Status code for this specific failure, which may differ from the HTTP status. */
    global Integer code {
        get { return getInteger('code'); }
    }

    /**
     * EINs this error applies to, for bulk requests.
     *
     * The API sends either an array or a comma-separated string; both are
     * flattened to a list here. Never null — an absent field yields an empty list.
     */
    global List<String> eins {
        get {
            List<String> result = new List<String>();
            Object value = get('eins');

            if (value instanceof List<Object>) {
                for (Object entry : (List<Object>) value) {
                    if (entry instanceof String) {
                        result.add((String) entry);
                    }
                }
            } else if (value instanceof String) {
                for (String part : ((String) value).split(',')) {
                    if (String.isNotBlank(part)) {
                        result.add(part.trim());
                    }
                }
            }

            return result;
        }
    }
}
