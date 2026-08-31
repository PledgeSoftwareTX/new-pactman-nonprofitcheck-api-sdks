/**
 * Input failed local validation. No callout was made.
 *
 * Distinguishable from an API-side 400 by `origin == ErrorOrigin.LOCAL`.
 */
global class ValidationException extends PactmanException {
    /** Every value that failed, in the order supplied. Never null. */
    global List<ValidationIssue> issues { get; private set; }

    /** Package-internal. */
    public ValidationException initIssues(List<ValidationIssue> issues) {
        this.issues = issues == null ? new List<ValidationIssue>() : issues;
        return this;
    }
}
