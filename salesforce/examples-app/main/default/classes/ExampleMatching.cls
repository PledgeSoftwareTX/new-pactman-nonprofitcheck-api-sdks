/**
 * Name comparison for the onboarding examples.
 *
 * None of this is part of the SDK, and deliberately so. The API returns the
 * identity IRS records hold; deciding whether "St. Mary's Hosp" and "SAINT MARYS
 * HOSPITAL INC" are the same applicant is a customer policy question, and the
 * answer differs between a donation platform, a DAF and a payroll-giving system.
 *
 * The comparisons below are conservative on purpose:
 *
 * - punctuation, casing, spacing and common abbreviations are not differences
 * - a value the API did not return is never scored as agreement
 * - the outcome is a routing hint, never a fraud finding
 */
@IsTest
public class ExampleMatching {
    /** The names are the same once formatting is normalized away. */
    public static final String AGREE = 'AGREE';

    /** Both names are present and they are not the same. */
    public static final String DIFFER = 'DIFFER';

    /** One side is missing, so there is nothing to compare. */
    public static final String UNCOMPARABLE = 'UNCOMPARABLE';

    /** Legal suffixes that carry no identifying information. */
    private static final Set<String> LEGAL_SUFFIXES = new Set<String>{
        'INC', 'INCORPORATED', 'LLC', 'LTD', 'CO', 'CORP', 'CORPORATION'
    };

    /** Abbreviations seen in IRS records versus what applicants type. */
    private static final Map<String, String> ABBREVIATIONS = new Map<String, String>{
        'ASSN' => 'ASSOCIATION',
        'ASSOC' => 'ASSOCIATION',
        'CTR' => 'CENTER',
        'CENTRE' => 'CENTER',
        'FDN' => 'FOUNDATION',
        'FND' => 'FOUNDATION',
        'INTL' => 'INTERNATIONAL',
        'NATL' => 'NATIONAL',
        'ORG' => 'ORGANIZATION',
        'SOC' => 'SOCIETY',
        'ST' => 'SAINT',
        'UNIV' => 'UNIVERSITY',
        'DEPT' => 'DEPARTMENT',
        'MT' => 'MOUNT'
    };

    /**
     * Reduces a name to the words that identify it.
     *
     * Case, punctuation, spacing, common abbreviations and legal suffixes all
     * come out, because none of them distinguish one organization from another.
     * Returns `null` when nothing is left to compare.
     */
    public static String normalizeName(String name) {
        if (String.isBlank(name)) {
            return null;
        }

        String cleaned = name.toUpperCase()
            .replace('&', ' AND ')
            .replaceAll('[^A-Z0-9]+', ' ')
            .trim();

        if (cleaned == '') {
            return null;
        }

        List<String> words = new List<String>();

        for (String word : cleaned.split(' ')) {
            if (word == '') {
                continue;
            }

            String expanded = ABBREVIATIONS.containsKey(word) ? ABBREVIATIONS.get(word) : word;

            if (LEGAL_SUFFIXES.contains(expanded)) {
                continue;
            }

            words.add(expanded);
        }

        return words.isEmpty() ? null : String.join(words, ' ');
    }

    /**
     * Compares two names.
     *
     * A missing side is {@link UNCOMPARABLE}, never agreement: scoring an
     * absent value as a match is how a blank record passes a name check.
     */
    public static String compareNames(String left, String right) {
        String first = normalizeName(left);
        String second = normalizeName(right);

        if (first == null || second == null) {
            return UNCOMPARABLE;
        }

        return first == second ? AGREE : DIFFER;
    }

    /**
     * The share of words the two names have in common, as evidence for a review
     * queue rather than a threshold to automate on. `null` when either side is
     * missing.
     */
    public static Decimal wordOverlap(String left, String right) {
        String first = normalizeName(left);
        String second = normalizeName(right);

        if (first == null || second == null) {
            return null;
        }

        Set<String> inFirst = new Set<String>(first.split(' '));
        Set<String> inSecond = new Set<String>(second.split(' '));

        Set<String> shared = inFirst.clone();
        shared.retainAll(inSecond);

        Set<String> union = inFirst.clone();
        union.addAll(inSecond);

        if (union.isEmpty()) {
            return null;
        }

        return ((Decimal) shared.size() / union.size()).setScale(2);
    }
}
