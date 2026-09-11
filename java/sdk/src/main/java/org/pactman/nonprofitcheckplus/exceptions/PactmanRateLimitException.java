package org.pactman.nonprofitcheckplus.exceptions;

/** HTTP 429. {@link #retryAfterSeconds()} carries the server's {@code Retry-After} when it sent one. */
public class PactmanRateLimitException extends PactmanApiException {

    private static final long serialVersionUID = 1L;

    /**
     * Creates the exception.
     *
     * @param message the message to surface.
     * @param init    the response metadata.
     */
    public PactmanRateLimitException(String message, ApiErrorInit init) {
        super(message, init, ErrorCategory.RATE_LIMIT);
    }
}
