package org.pactman.nonprofitcheckplus.exceptions;

import java.util.Map;

/**
 * The request produced no HTTP response, or the caller cancelled it.
 *
 * <p>A cancelled call — the calling thread interrupted, or the
 * {@link java.util.concurrent.CompletableFuture} from an async method
 * cancelled — arrives here rather than as a timeout: nothing expired, someone
 * asked for the work to stop.
 */
public class PactmanNetworkException extends PactmanException {

    private static final long serialVersionUID = 1L;

    /** @serial how many attempts were made. */
    private final int attempts;

    /**
     * Creates the exception.
     *
     * @param message  what failed.
     * @param attempts how many attempts were made.
     * @param cause    the underlying failure, or {@code null}.
     */
    public PactmanNetworkException(String message, int attempts, Throwable cause) {
        super(message, ErrorCategory.NETWORK, ErrorOrigin.LOCAL, cause);
        this.attempts = attempts;
    }

    /**
     * How many attempts were made before this error was surfaced.
     *
     * @return the attempt count. Zero when the call was cancelled before any attempt.
     */
    public int attempts() {
        return attempts;
    }

    @Override
    public Map<String, Object> toMap() {
        Map<String, Object> fields = super.toMap();
        fields.put("attempts", attempts);

        return fields;
    }
}
