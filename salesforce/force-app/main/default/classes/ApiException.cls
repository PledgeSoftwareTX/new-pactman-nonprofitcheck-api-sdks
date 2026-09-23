/**
 * An error returned by the Pactman API.
 *
 * Thrown directly when the status maps to no more specific subclass. Response
 * metadata is preserved even when the body could not be parsed as JSON.
 */
global virtual class ApiException extends PactmanException {
    /** HTTP status of the response. */
    global Integer status { get; private set; }

    /** `message` from the Pactman response envelope, when present. */
    global String apiMessage { get; private set; }

    /** `code` from the Pactman response envelope, when present. */
    global Integer apiCode { get; private set; }

    /** `errors` from the envelope, normalized to a list. Never null. */
    global List<ApiErrorDetail> apiErrors { get; private set; }

    /** Correlation identifier from the response headers, when the server sent one. */
    global String requestId { get; private set; }

    /** `Retry-After` in seconds, when the server supplied a valid value. */
    global Decimal retryAfterSeconds { get; private set; }

    /** The parsed response body, or the raw text when it was not JSON. */
    global Object raw { get; private set; }

    /** How many attempts were made before this exception was surfaced. */
    global Integer attempts { get; private set; }

    /** Package-internal. */
    public ApiException initApi(ApiErrorInit init) {
        this.status = init.status;
        this.apiMessage = init.apiMessage;
        this.apiCode = init.apiCode;
        this.apiErrors = init.apiErrors == null ? new List<ApiErrorDetail>() : init.apiErrors;
        this.requestId = init.requestId;
        this.retryAfterSeconds = init.retryAfterSeconds;
        this.raw = init.raw;
        this.attempts = init.attempts == null ? 1 : init.attempts;
        return this;
    }
}
