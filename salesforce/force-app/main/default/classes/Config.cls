/**
 * Client configuration.
 *
 * **There is no `apiKey` option, deliberately.** The other Pactman SDKs take
 * the key as a constructor argument and work hard to keep it out of logs and
 * serialized output. Salesforce already has an encrypted, admin-managed store
 * for exactly this, so the key lives in an External Credential behind a Named
 * Credential and the platform injects the `Authorization` header at callout
 * time. Apex never sees it, which means it cannot leak through a debug log, an
 * exception, or a serialized client.
 *
 * Apex has no named or optional parameters, so options are set fluently:
 *
 * ```
 * pactman.Config config = new pactman.Config()
 *     .withNamedCredential('My_Pactman_Credential')
 *     .withTimeoutMs(10000);
 * ```
 */
global class Config {
    /** The Named Credential callouts are sent through. */
    global String namedCredential { get; private set; }

    /** An explicit endpoint, when one was set. Overrides {@link namedCredential}. */
    global String endpointOverride { get; private set; }

    /** Timeout per callout, in milliseconds. */
    global Integer timeoutMs { get; private set; }

    private final Map<String, String> defaultHeaders = new Map<String, String>();

    global Config() {
        this.namedCredential = Constants.DEFAULT_NAMED_CREDENTIAL;
        this.timeoutMs = Constants.DEFAULT_TIMEOUT_MS;
    }

    /** Sends through a different Named Credential than the packaged default. */
    global Config withNamedCredential(String name) {
        if (String.isBlank(name)) {
            throw Errors.configuration('namedCredential cannot be blank.');
        }

        this.namedCredential = name.trim();
        return this;
    }

    /**
     * Sends to an explicit endpoint instead of a Named Credential.
     *
     * For a mock server or a host Pactman has given you directly. The org still
     * needs a Remote Site Setting for it, and **no `Authorization` header is
     * added** — this path exists for testing, not for production traffic.
     */
    global Config withEndpoint(String url) {
        if (String.isBlank(url)) {
            throw Errors.configuration('endpoint cannot be blank.');
        }

        String trimmed = url.trim().removeEnd('/');

        if (!trimmed.startsWith('http://') && !trimmed.startsWith('https://')) {
            throw Errors.configuration('endpoint must be an absolute http(s) URL. Received "' + url + '".');
        }

        this.endpointOverride = trimmed;
        return this;
    }

    /**
     * Timeout per callout, in milliseconds.
     *
     * Salesforce caps a single callout at {@link Constants.MAX_TIMEOUT_MS}, and
     * separately caps the total callout time in one transaction at 120 seconds
     * across every callout it makes.
     */
    global Config withTimeoutMs(Integer ms) {
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

    /** Adds a header sent with every request. Cannot set `Authorization`. */
    global Config withHeader(String name, String value) {
        if (String.isBlank(name)) {
            throw Errors.configuration('A default header name cannot be blank.');
        }

        if (name.equalsIgnoreCase('Authorization')) {
            throw Errors.configuration(
                'Authorization cannot be set from Apex. The API key belongs in the External ' +
                    'Credential behind the Named Credential.'
            );
        }

        defaultHeaders.put(name, value);
        return this;
    }

    /** The headers sent with every request. A copy. */
    global Map<String, String> headers() {
        return defaultHeaders.clone();
    }

    /** The resolved endpoint prefix every request is sent to. Package-internal. */
    public String resolvedEndpoint() {
        return endpointOverride != null ? endpointOverride : 'callout:' + namedCredential;
    }

    /** A view of the configuration for logging. Contains no credential. */
    global Map<String, Object> toMap() {
        return new Map<String, Object>{
            'namedCredential' => namedCredential,
            'endpointOverride' => endpointOverride,
            'timeoutMs' => timeoutMs,
            'userAgent' => SdkVersion.userAgent()
        };
    }
}
