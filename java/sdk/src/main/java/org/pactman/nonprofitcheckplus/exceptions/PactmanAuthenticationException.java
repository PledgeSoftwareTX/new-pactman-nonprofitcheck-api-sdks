package org.pactman.nonprofitcheckplus.exceptions;

/** HTTP 401. */
public class PactmanAuthenticationException extends PactmanApiException {

    private static final long serialVersionUID = 1L;

    /**
     * Creates the exception.
     *
     * @param message the message to surface.
     * @param init    the response metadata.
     */
    public PactmanAuthenticationException(String message, ApiErrorInit init) {
        super(message, init, ErrorCategory.AUTHENTICATION);
    }
}
