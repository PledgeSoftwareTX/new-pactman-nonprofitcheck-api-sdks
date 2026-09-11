package org.pactman.nonprofitcheckplus.exceptions;

/** HTTP 5xx. */
public class PactmanServerException extends PactmanApiException {

    private static final long serialVersionUID = 1L;

    /**
     * Creates the exception.
     *
     * @param message the message to surface.
     * @param init    the response metadata.
     */
    public PactmanServerException(String message, ApiErrorInit init) {
        super(message, init, ErrorCategory.SERVER);
    }
}
