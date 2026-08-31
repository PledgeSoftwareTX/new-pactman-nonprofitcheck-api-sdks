/**
 * EIN normalization and validation.
 *
 * Formatting validation only. Passing these checks says nothing about whether
 * an organization is tax-exempt, in good standing, or eligible for anything —
 * only that the value is shaped like an EIN. No IRS prefix rules are applied.
 *
 * The other SDKs also reject non-string input at runtime. Apex is statically
 * typed, so that case cannot arise here and no equivalent check exists.
 */
global class Ein {
    /** Number of digits in an EIN. */
    global static final Integer LENGTH = 9;

    /**
     * Accepted input shapes: nine digits, optionally with the conventional
     * hyphen after the two-digit prefix. Surrounding whitespace is ignored.
     */
    private static final Pattern EIN_PATTERN = Pattern.compile('^\\d{2}-?\\d{7}$');

    /**
     * Normalizes an EIN to the nine-digit form the API expects.
     *
     * `'41-1787097'` and `'411787097'` both normalize to `'411787097'`.
     *
     * @throws ValidationException if the value is not shaped like an EIN.
     */
    global static String normalize(String value) {
        return normalize(value, null);
    }

    /**
     * Normalizes an EIN, reporting its position in a collection on failure.
     *
     * @throws ValidationException if the value is not shaped like an EIN.
     */
    global static String normalize(String value, Integer index) {
        ValidationIssue issue = issueFor(value, index);

        if (issue != null) {
            throw Errors.validation(issue.message, new List<ValidationIssue>{ issue });
        }

        return clean(value);
    }

    /**
     * Normalizes a collection of EINs, reporting every failure at once.
     *
     * Duplicates are preserved and order is retained; see
     * {@link Nonprofits.checkBulk} for the optional dedupe behaviour.
     *
     * @throws ValidationException if any item is not shaped like an EIN. The
     *     exception's `issues` identify the failing item by index and original
     *     value.
     */
    global static List<String> normalizeMany(List<String> values) {
        List<ValidationIssue> issues = new List<ValidationIssue>();
        List<String> normalized = new List<String>();
        Integer count = 0;

        if (values != null) {
            for (String value : values) {
                ValidationIssue issue = issueFor(value, count);
                count++;

                if (issue != null) {
                    issues.add(issue);
                    continue;
                }

                normalized.add(clean(value));
            }
        }

        if (!issues.isEmpty()) {
            List<String> positions = new List<String>();

            for (ValidationIssue issue : issues) {
                positions.add(String.valueOf(issue.index));
            }

            throw Errors.validation(
                issues.size() + ' of ' + count + ' EINs are invalid (at index ' +
                    String.join(positions, ', ') + '). No request was sent.',
                issues
            );
        }

        return normalized;
    }

    /** True when `value` is shaped like an EIN. Never throws. */
    global static Boolean isValid(String value) {
        return issueFor(value, null) == null;
    }

    /**
     * Splits EINs into batches the bulk endpoint will accept.
     *
     * The other SDKs deliberately do not chunk inside `checkBulk`, and neither
     * does this one — silently splitting would misreport how much quota a call
     * consumed. This helper is the explicit alternative, and it matters more in
     * Apex than elsewhere: a transaction is capped at 100 callouts, so the
     * number of batches is something you have to reason about.
     */
    global static List<List<String>> chunk(List<String> values) {
        List<List<String>> batches = new List<List<String>>();

        if (values == null || values.isEmpty()) {
            return batches;
        }

        List<String> current = new List<String>();

        for (String value : values) {
            current.add(value);

            if (current.size() == Constants.MAX_BULK_EINS) {
                batches.add(current);
                current = new List<String>();
            }
        }

        if (!current.isEmpty()) {
            batches.add(current);
        }

        return batches;
    }

    private static String clean(String value) {
        return value.trim().replace('-', '');
    }

    private static ValidationIssue issueFor(String value, Integer index) {
        String at = index == null ? '' : ' at index ' + index;

        if (value == null) {
            return new ValidationIssue('EIN' + at + ' is required.', index, value);
        }

        String trimmed = value.trim();

        if (trimmed == '') {
            return new ValidationIssue('EIN' + at + ' is empty.', index, value);
        }

        if (!EIN_PATTERN.matcher(trimmed).matches()) {
            return new ValidationIssue(
                'EIN' + at + ' must be ' + LENGTH +
                    ' digits, optionally hyphenated as XX-XXXXXXX. Received "' + trimmed + '".',
                index,
                value
            );
        }

        return null;
    }
}
