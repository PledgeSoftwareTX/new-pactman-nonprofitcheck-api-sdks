/**
 * Stable, machine-comparable error categories.
 *
 * Lowercased, these names are the exact strings the Node, Python and PHP SDKs
 * report for the same failure, so a category logged by an Apex org matches one
 * logged by a Node service. `ErrorsTest` pins every value; do not rename a
 * constant without changing that test deliberately.
 */
global enum ErrorCategory {
    /** The client was constructed with unusable options. */
    CONFIGURATION,
    /** Input failed the SDK's local validation; no request was sent. */
    VALIDATION,
    /** HTTP 401. The API key is missing, malformed, revoked or unrecognized. */
    AUTHENTICATION,
    /** HTTP 403. The key is valid but lacks access to the resource. */
    AUTHORIZATION,
    /** HTTP 400. The API rejected the request. */
    BAD_REQUEST,
    /** HTTP 404. No matching record. */
    NOT_FOUND,
    /** HTTP 429. Rate limit exceeded. */
    RATE_LIMIT,
    /** HTTP 5xx. */
    SERVER,
    /** The request exceeded the configured timeout. */
    TIMEOUT,
    /** The request never produced an HTTP response. */
    NETWORK,
    /** An API error that does not fall into a more specific category. */
    API
}
