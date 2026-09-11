package org.pactman.nonprofitcheckplus.internal;

/**
 * A JSON document could not be read or written.
 *
 * <p>Internal. The transport catches this and keeps the undecodable payload as
 * text, so a response that is not JSON is still surfaced as evidence rather
 * than as a parse failure with the body discarded.
 */
public final class JsonException extends RuntimeException {

    private static final long serialVersionUID = 1L;

    /**
     * Creates the exception.
     *
     * @param message what went wrong.
     */
    public JsonException(String message) {
        super(message);
    }
}
