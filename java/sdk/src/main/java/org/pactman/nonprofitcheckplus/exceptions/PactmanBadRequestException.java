package org.pactman.nonprofitcheckplus.exceptions;

/** HTTP 400. The API rejected the request; see {@link #apiErrors()} for the reasons. */
public class PactmanBadRequestException extends PactmanApiException {

    private static final long serialVersionUID = 1L;

    /**
     * Creates the exception.
     *
     * @param message the message to surface.
     * @param init    the response metadata.
     */
    public PactmanBadRequestException(String message, ApiErrorInit init) {
        super(message, init, ErrorCategory.BAD_REQUEST);
    }
}
