package org.pactman.nonprofitcheckplus.examples.support;

import java.util.Arrays;
import java.util.Collections;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.Locale;
import java.util.Map;
import java.util.Set;

/**
 * Name comparison for the onboarding examples.
 *
 * <p>None of this is part of the SDK, and deliberately so. The API returns the
 * identity IRS records hold; deciding whether "St. Mary's Hosp" and "SAINT MARYS
 * HOSPITAL INC" are the same applicant is a customer policy question, and the
 * answer differs between a donation platform, a DAF and a payroll-giving system.
 *
 * <p>The comparisons below are conservative on purpose:
 *
 * <ul>
 *   <li>punctuation, casing, spacing and common abbreviations are not differences
 *   <li>a value the API did not return is never scored as agreement
 *   <li>the outcome is a routing hint, never a fraud finding
 * </ul>
 */
public final class Matching {

    /** How two names compared. Never a verdict about the applicant. */
    public enum Comparison {
        /** The names are the same once formatting is normalized away. */
        AGREE,
        /** Both names are present and they are not the same. */
        DIFFER,
        /** One side is missing, so there is nothing to compare. */
        UNCOMPARABLE
    }

    /** Legal suffixes that carry no identifying information. */
    private static final Set<String> LEGAL_SUFFIXES = new HashSet<>(Arrays.asList(
            "INC", "INCORPORATED", "LLC", "LTD", "CO", "CORP", "CORPORATION"));

    /** Abbreviations seen in IRS records versus what applicants type. */
    private static final Map<String, String> ABBREVIATIONS = abbreviations();

    private Matching() {
    }

    private static Map<String, String> abbreviations() {
        Map<String, String> map = new LinkedHashMap<>();
        map.put("&", "AND");
        map.put("ASSN", "ASSOCIATION");
        map.put("ASSOC", "ASSOCIATION");
        map.put("CTR", "CENTER");
        map.put("CENTRE", "CENTER");
        map.put("FDN", "FOUNDATION");
        map.put("FND", "FOUNDATION");
        map.put("INTL", "INTERNATIONAL");
        map.put("NATL", "NATIONAL");
        map.put("ORG", "ORGANIZATION");
        map.put("SOC", "SOCIETY");
        map.put("ST", "SAINT");
        map.put("UNIV", "UNIVERSITY");
        map.put("DEPT", "DEPARTMENT");
        map.put("MT", "MOUNT");

        return Collections.unmodifiableMap(map);
    }

    /**
     * Reduces a name to the words that identify it.
     *
     * <p>Case, punctuation, spacing, common abbreviations and legal suffixes all
     * come out, because none of them distinguish one organization from another.
     *
     * @param name the name as written, or {@code null}.
     * @return the normalized form, or {@code null} when there is nothing to compare.
     */
    public static String normalizeName(String name) {
        if (name == null || name.trim().isEmpty()) {
            return null;
        }

        String cleaned = name.toUpperCase(Locale.ROOT)
                .replace("&", " AND ")
                .replaceAll("[^A-Z0-9]+", " ")
                .trim();

        if (cleaned.isEmpty()) {
            return null;
        }

        StringBuilder normalized = new StringBuilder();

        for (String word : cleaned.split(" ")) {
            String expanded = ABBREVIATIONS.getOrDefault(word, word);

            if (LEGAL_SUFFIXES.contains(expanded)) {
                continue;
            }

            if (normalized.length() > 0) {
                normalized.append(' ');
            }

            normalized.append(expanded);
        }

        return normalized.length() == 0 ? null : normalized.toString();
    }

    /**
     * Compares two names.
     *
     * @param left  one name, or {@code null}.
     * @param right the other, or {@code null}.
     * @return how they compared. A missing side is {@link Comparison#UNCOMPARABLE},
     *         never agreement.
     */
    public static Comparison compareNames(String left, String right) {
        String a = normalizeName(left);
        String b = normalizeName(right);

        if (a == null || b == null) {
            return Comparison.UNCOMPARABLE;
        }

        return a.equals(b) ? Comparison.AGREE : Comparison.DIFFER;
    }

    /**
     * The share of words the two names have in common, as evidence for a review
     * queue rather than a threshold to automate on.
     *
     * @param left  one name, or {@code null}.
     * @param right the other, or {@code null}.
     * @return a value in {@code [0, 1]}, or {@code null} when either side is missing.
     */
    public static Double wordOverlap(String left, String right) {
        String a = normalizeName(left);
        String b = normalizeName(right);

        if (a == null || b == null) {
            return null;
        }

        Set<String> first = new LinkedHashSet<>(Arrays.asList(a.split(" ")));
        Set<String> second = new LinkedHashSet<>(Arrays.asList(b.split(" ")));
        Set<String> shared = new LinkedHashSet<>(first);
        shared.retainAll(second);

        Set<String> union = new LinkedHashSet<>(first);
        union.addAll(second);

        return union.isEmpty() ? null : (double) shared.size() / union.size();
    }
}
