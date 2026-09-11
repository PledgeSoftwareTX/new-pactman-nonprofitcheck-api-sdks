package org.pactman.nonprofitcheckplus.exceptions;

import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.Map;

/**
 * Input failed local validation. No HTTP request was sent.
 *
 * <p>Distinguishable from an API-side 400 by {@link #origin()} being
 * {@link ErrorOrigin#LOCAL}.
 */
public class PactmanValidationException extends PactmanException {

    private static final long serialVersionUID = 1L;

    /**
     * The failing items. Not serialized: an issue carries the caller's own
     * value, which need not be {@link java.io.Serializable}. A deserialized
     * exception reports an empty list and keeps its message.
     */
    private final transient List<ValidationIssue> issues;

    /**
     * Creates the exception with no itemized issues.
     *
     * @param message what was wrong with the input.
     */
    public PactmanValidationException(String message) {
        this(message, Collections.emptyList());
    }

    /**
     * Creates the exception.
     *
     * @param message what was wrong with the input.
     * @param issues  every item that failed, so one call reports them all.
     */
    public PactmanValidationException(String message, List<ValidationIssue> issues) {
        super(message, ErrorCategory.VALIDATION, ErrorOrigin.LOCAL, null);
        this.issues = Collections.unmodifiableList(
                new ArrayList<>(issues == null ? Collections.<ValidationIssue>emptyList() : issues));
    }

    /**
     * Every item that failed validation.
     *
     * @return the issues, in input order. Empty when the input failed as a whole.
     */
    public List<ValidationIssue> issues() {
        return issues == null ? Collections.<ValidationIssue>emptyList() : issues;
    }

    @Override
    public Map<String, Object> toMap() {
        Map<String, Object> fields = super.toMap();
        List<Map<String, Object>> reported = new ArrayList<>(issues().size());

        for (ValidationIssue issue : issues()) {
            reported.add(issue.toMap());
        }

        fields.put("issues", reported);

        return fields;
    }
}
