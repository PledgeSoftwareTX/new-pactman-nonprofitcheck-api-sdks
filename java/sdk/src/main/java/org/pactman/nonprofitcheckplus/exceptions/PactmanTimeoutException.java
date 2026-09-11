package org.pactman.nonprofitcheckplus.exceptions;

import java.util.Map;

/** The request exceeded the configured timeout. */
public class PactmanTimeoutException extends PactmanException {

    private static final long serialVersionUID = 1L;

    /** @serial the timeout that was exceeded, in milliseconds. */
    private final long timeoutMs;

    /** @serial how many attempts were made. */
    private final int attempts;

    /**
     * Creates the exception.
     *
     * @param message   what timed out.
     * @param timeoutMs the timeout that was exceeded, in milliseconds.
     * @param attempts  how many attempts were made.
     * @param cause     the underlying failure, or {@code null}.
     */
    public PactmanTimeoutException(String message, long timeoutMs, int attempts, Throwable cause) {
        super(message, ErrorCategory.TIMEOUT, ErrorOrigin.LOCAL, cause);
        this.timeoutMs = timeoutMs;
        this.attempts = attempts;
    }

    /**
     * The timeout that was exceeded.
     *
     * @return the timeout in milliseconds.
     */
    public long timeoutMs() {
        return timeoutMs;
    }

    /**
     * How many attempts were made before this error was surfaced.
     *
     * @return the attempt count, counting the first attempt as one.
     */
    public int attempts() {
        return attempts;
    }

    @Override
    public Map<String, Object> toMap() {
        Map<String, Object> fields = super.toMap();
        fields.put("timeoutMs", timeoutMs);
        fields.put("attempts", attempts);

        return fields;
    }
}
