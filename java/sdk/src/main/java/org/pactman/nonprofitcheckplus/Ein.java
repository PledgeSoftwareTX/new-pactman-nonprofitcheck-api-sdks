package org.pactman.nonprofitcheckplus;

import java.util.ArrayList;
import java.util.List;
import java.util.regex.Pattern;
import org.pactman.nonprofitcheckplus.exceptions.PactmanValidationException;
import org.pactman.nonprofitcheckplus.exceptions.ValidationIssue;

/**
 * EIN normalization and validation.
 *
 * <p>Formatting validation only. Passing these checks says nothing about whether
 * an organization is tax-exempt, in good standing, or eligible for anything —
 * only that the value is shaped like an EIN. No IRS prefix rules are applied.
 */
public final class Ein {

    /** Number of digits in an EIN. */
    public static final int EIN_LENGTH = 9;

    /**
     * Accepted input shapes: nine digits, optionally with the conventional
     * hyphen after the two-digit prefix. Surrounding whitespace is ignored.
     */
    private static final Pattern EIN_PATTERN = Pattern.compile("^\\d{2}-?\\d{7}$");

    private Ein() {
    }

    /**
     * Normalizes an EIN to the nine-digit form the API expects.
     *
     * <p>{@code "41-1787097"} and {@code "411787097"} both normalize to
     * {@code "411787097"}.
     *
     * @param input the EIN as supplied.
     * @return the nine-digit EIN.
     * @throws PactmanValidationException if the value is not shaped like an EIN.
     */
    public static String normalize(String input) {
        return normalize(input, null);
    }

    /**
     * Normalizes an EIN, reporting its position in a collection.
     *
     * @param input the EIN as supplied.
     * @param index the position in the caller's collection, or {@code null}.
     * @return the nine-digit EIN.
     * @throws PactmanValidationException if the value is not shaped like an EIN.
     */
    public static String normalize(String input, Integer index) {
        ValidationIssue issue = issueFor(input, index);

        if (issue != null) {
            throw new PactmanValidationException(
                    issue.message(), java.util.Collections.singletonList(issue));
        }

        return input.trim().replace("-", "");
    }

    /**
     * Normalizes a collection of EINs, reporting every failure at once.
     *
     * <p>Duplicates are preserved and order is retained; see
     * {@link NonprofitsResource#checkBulk(List, org.pactman.nonprofitcheckplus.config.BulkRequestOptions)}
     * for the optional dedupe behaviour.
     *
     * @param inputs the EINs as supplied.
     * @return the nine-digit EINs, in input order.
     * @throws PactmanValidationException if any item is not shaped like an EIN. The
     *         exception's issues identify each failing item by index and original value.
     */
    public static List<String> normalizeAll(List<String> inputs) {
        if (inputs == null) {
            throw new PactmanValidationException("A list of EINs is required, received null.");
        }

        List<ValidationIssue> issues = new ArrayList<>();
        List<String> normalized = new ArrayList<>(inputs.size());

        for (int index = 0; index < inputs.size(); index++) {
            String input = inputs.get(index);
            ValidationIssue issue = issueFor(input, index);

            if (issue != null) {
                issues.add(issue);
                continue;
            }

            normalized.add(input.trim().replace("-", ""));
        }

        if (!issues.isEmpty()) {
            StringBuilder positions = new StringBuilder();

            for (int i = 0; i < issues.size(); i++) {
                if (i > 0) {
                    positions.append(", ");
                }

                positions.append(issues.get(i).index());
            }

            throw new PactmanValidationException(
                    issues.size() + " of " + inputs.size() + " EINs are invalid (at index "
                            + positions + "). No request was sent.",
                    issues);
        }

        return normalized;
    }

    /**
     * True when the input is shaped like an EIN. Never throws.
     *
     * @param input the value to check.
     * @return whether the value is shaped like an EIN.
     */
    public static boolean isValid(String input) {
        return issueFor(input, null) == null;
    }

    private static ValidationIssue issueFor(String input, Integer index) {
        String at = index == null ? "" : " at index " + index;

        if (input == null) {
            return new ValidationIssue("EIN" + at + " is required.", index, null);
        }

        String trimmed = input.trim();

        if (trimmed.isEmpty()) {
            return new ValidationIssue("EIN" + at + " is empty.", index, input);
        }

        if (!EIN_PATTERN.matcher(trimmed).matches()) {
            return new ValidationIssue(
                    "EIN" + at + " must be " + EIN_LENGTH
                            + " digits, optionally hyphenated as XX-XXXXXXX. Received \""
                            + trimmed + "\".",
                    index,
                    input);
        }

        return null;
    }
}
