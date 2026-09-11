package org.pactman.nonprofitcheckplus.exceptions;

/** The client options were unusable — a missing API key, a malformed base URL. */
public class PactmanConfigurationException extends PactmanException {

    private static final long serialVersionUID = 1L;

    /**
     * Creates the exception.
     *
     * @param message what was wrong with the options.
     */
    public PactmanConfigurationException(String message) {
        super(message, ErrorCategory.CONFIGURATION, ErrorOrigin.LOCAL, null);
    }
}
