/**
 * The API surface this SDK wraps, declared once.
 *
 * Nothing else in this package contains an endpoint path or a batch limit.
 */
global class Constants {
    /** Path of the single-check endpoint. `{ein}` is replaced with a normalized EIN. */
    global static final String SINGLE_CHECK_PATH = '/api/entities/nonprofitcheck/v1/us/ein/{ein}';

    /** Path of the bulk-check endpoint. */
    global static final String BULK_CHECK_PATH = '/api/entities/nonprofitcheckbulk/v1/us/eins';

    /**
     * Maximum number of EINs the API accepts in one bulk request.
     *
     * This mirrors the server-side limit. It is declared once, here.
     */
    global static final Integer MAX_BULK_EINS = 50;

    /**
     * The Named Credential the SDK calls through when none is configured.
     *
     * The API key lives in the External Credential behind this, never in Apex.
     */
    global static final String DEFAULT_NAMED_CREDENTIAL = 'Pactman_Nonprofit_Check';

    /** Timeout applied to a callout when none is configured, in milliseconds. */
    global static final Integer DEFAULT_TIMEOUT_MS = 30000;

    /**
     * The platform's hard ceiling on a single callout, in milliseconds.
     *
     * Salesforce rejects anything above this, so the SDK refuses it up front
     * rather than letting the callout fail at send time.
     */
    global static final Integer MAX_TIMEOUT_MS = 120000;
}
