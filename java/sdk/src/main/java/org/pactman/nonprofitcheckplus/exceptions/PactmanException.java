package org.pactman.nonprofitcheckplus.exceptions;

import java.util.LinkedHashMap;
import java.util.Map;

/**
 * Base class for every exception this SDK throws.
 *
 * <p>Unchecked, so a lookup composes inside a stream or a lambda without a
 * wrapper; the failures worth handling are worth handling deliberately, at the
 * level that can act on them, rather than at every call site.
 *
 * <p>API keys are never placed into an exception message, an exception
 * property, or {@link #toMap()}.
 */
public class PactmanException extends RuntimeException {

    private static final long serialVersionUID = 1L;

    /** @serial the stable category callers may branch on. */
    private final ErrorCategory category;

    /** @serial whether this was raised locally or by the API. */
    private final ErrorOrigin origin;

    /**
     * Creates the exception.
     *
     * @param message   what went wrong.
     * @param category  the stable category callers may branch on.
     * @param origin    whether this was raised locally or by the API.
     * @param cause     the underlying failure, or {@code null}.
     */
    protected PactmanException(
            String message, ErrorCategory category, ErrorOrigin origin, Throwable cause) {
        super(message, cause);
        this.category = category;
        this.origin = origin;
    }

    /**
     * The stable category of this failure.
     *
     * @return the category.
     */
    public ErrorCategory category() {
        return category;
    }

    /**
     * Whether this was raised locally or derived from an API response.
     *
     * @return the origin.
     */
    public ErrorOrigin origin() {
        return origin;
    }

    /**
     * A redacted, loggable view of this exception.
     *
     * <p>The API key is not a property of this object and never appears here.
     *
     * @return the exception's fields, in a stable order.
     */
    public Map<String, Object> toMap() {
        Map<String, Object> fields = new LinkedHashMap<>();
        fields.put("name", getClass().getSimpleName());
        fields.put("message", getMessage());
        fields.put("category", category.wireName());
        fields.put("origin", origin.wireName());

        return fields;
    }
}
