package org.pactman.nonprofitcheckplus.exceptions;

/** HTTP 403. */
public class PactmanAuthorizationException extends PactmanApiException {

    private static final long serialVersionUID = 1L;

    /**
     * Creates the exception.
     *
     * @param message the message to surface.
     * @param init    the response metadata.
     */
    public PactmanAuthorizationException(String message, ApiErrorInit init) {
        super(message, init, ErrorCategory.AUTHORIZATION);
    }
}
