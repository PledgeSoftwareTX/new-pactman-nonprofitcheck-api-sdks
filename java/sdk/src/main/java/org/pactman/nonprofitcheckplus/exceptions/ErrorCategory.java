package org.pactman.nonprofitcheckplus.exceptions;

/**
 * A stable, machine-comparable error category.
 *
 * <p>Every exception this SDK throws carries one, so callers can branch on the
 * category — or on the exception type — without parsing message strings.
 */
public enum ErrorCategory {

    /** The client was constructed with unusable options. */
    CONFIGURATION("configuration"),

    /** Input failed the SDK's local validation; no request was sent. */
    VALIDATION("validation"),

    /** HTTP 401. The API key is missing, malformed, revoked or unrecognized. */
    AUTHENTICATION("authentication"),

    /** HTTP 403. The key is valid but lacks access to the resource. */
    AUTHORIZATION("authorization"),

    /** HTTP 400. The API rejected the request. */
    BAD_REQUEST("bad_request"),

    /** HTTP 404. No matching record. */
    NOT_FOUND("not_found"),

    /** HTTP 429. Rate limit exceeded. */
    RATE_LIMIT("rate_limit"),

    /** HTTP 5xx. */
    SERVER("server"),

    /** The request exceeded the configured timeout. */
    TIMEOUT("timeout"),

    /** The request never produced an HTTP response, or the caller cancelled it. */
    NETWORK("network"),

    /** An API error that does not fall into a more specific category. */
    API("api");

    private final String wireName;

    ErrorCategory(String wireName) {
        this.wireName = wireName;
    }

    /**
     * The category name the SDKs in every language share.
     *
     * @return the lowercase, underscore-separated name.
     */
    public String wireName() {
        return wireName;
    }

    @Override
    public String toString() {
        return wireName;
    }
}
