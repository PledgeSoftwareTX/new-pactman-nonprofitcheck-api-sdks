/**
 * Per-request overrides.
 *
 * Apex has no named or optional parameters, so these are set fluently:
 *
 * ```
 * client.nonprofits.check('41-1787097', new pactman.RequestOptions().withTimeoutMs(5000));
 * ```
 */
global class RequestOptions {
    /** Overrides the client's timeout for this request, or `null` to inherit it. */
    global Integer timeoutMs { get; private set; }

    /**
     * Remove duplicate EINs before sending, keeping first-seen order.
     *
     * Applies to {@link Nonprofits.checkBulk} only; ignored by a single check.
     * Off by default: duplicates are sent exactly as supplied, because each one
     * consumes quota and silently dropping them would misreport what was
     * checked.
     */
    global Boolean dedupe { get; private set; }

    private final Map<String, String> headers = new Map<String, String>();

    global RequestOptions() {
        this.dedupe = false;
    }

    /** Overrides the client's timeout for this request. */
    global RequestOptions withTimeoutMs(Integer ms) {
        if (ms == null || ms <= 0) {
            throw Errors.configuration('timeoutMs must be a positive number of milliseconds.');
        }

        if (ms > Constants.MAX_TIMEOUT_MS) {
            throw Errors.configuration(
                'timeoutMs cannot exceed ' + Constants.MAX_TIMEOUT_MS +
                    ' — Salesforce rejects a longer callout timeout. Received ' + ms + '.'
            );
        }

        this.timeoutMs = ms;
        return this;
    }

    /** Removes duplicate EINs before sending. Bulk only. */
    global RequestOptions withDedupe(Boolean dedupe) {
        this.dedupe = dedupe == true;
        return this;
    }

    /** Adds a header to this request. Cannot set `Authorization`. */
    global RequestOptions withHeader(String name, String value) {
        if (String.isBlank(name)) {
            throw Errors.configuration('A header name cannot be blank.');
        }

        if (name.equalsIgnoreCase('Authorization')) {
            throw Errors.configuration(
                'Authorization cannot be set from Apex. The API key belongs in the External ' +
                    'Credential behind the Named Credential.'
            );
        }

        headers.put(name, value);
        return this;
    }

    /** The headers set on this request. A copy. Package-internal. */
    public Map<String, String> headerMap() {
        return headers.clone();
    }
}
