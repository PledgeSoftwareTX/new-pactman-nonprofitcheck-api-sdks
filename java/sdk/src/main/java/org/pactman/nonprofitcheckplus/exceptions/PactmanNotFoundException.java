package org.pactman.nonprofitcheckplus.exceptions;

/** HTTP 404. */
public class PactmanNotFoundException extends PactmanApiException {

    private static final long serialVersionUID = 1L;

    /**
     * Creates the exception.
     *
     * @param message the message to surface.
     * @param init    the response metadata.
     */
    public PactmanNotFoundException(String message, ApiErrorInit init) {
        super(message, init, ErrorCategory.NOT_FOUND);
    }
}
