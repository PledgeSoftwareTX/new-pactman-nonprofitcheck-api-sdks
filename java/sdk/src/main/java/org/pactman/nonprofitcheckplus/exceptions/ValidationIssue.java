package org.pactman.nonprofitcheckplus.exceptions;

import java.util.LinkedHashMap;
import java.util.Map;

/** One item that failed local validation. */
public final class ValidationIssue {

    private final String message;
    private final Integer index;
    private final Object value;

    /**
     * Creates an issue.
     *
     * @param message human-readable reason the value was rejected.
     * @param index   position in the input collection, or {@code null} for a scalar input.
     * @param value   the offending value, as supplied by the caller.
     */
    public ValidationIssue(String message, Integer index, Object value) {
        this.message = message;
        this.index = index;
        this.value = value;
    }

    /**
     * Human-readable reason the value was rejected.
     *
     * @return the reason.
     */
    public String message() {
        return message;
    }

    /**
     * Position in the input collection, for bulk calls.
     *
     * @return the zero-based index, or {@code null} when the input was not a collection.
     */
    public Integer index() {
        return index;
    }

    /**
     * The offending value, as supplied by the caller.
     *
     * @return the value, which may be {@code null}.
     */
    public Object value() {
        return value;
    }

    /**
     * A loggable view of this issue.
     *
     * @return the issue's fields, in a stable order.
     */
    public Map<String, Object> toMap() {
        Map<String, Object> fields = new LinkedHashMap<>();
        fields.put("message", message);
        fields.put("index", index);
        fields.put("value", value);

        return fields;
    }

    @Override
    public String toString() {
        return index == null ? message : message + " (index " + index + ")";
    }
}
