package org.pactman.nonprofitcheckplus.examples.support;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.HashSet;
import java.util.List;
import java.util.Locale;
import java.util.Set;
import org.pactman.nonprofitcheckplus.models.Nonprofit;

/**
 * Address checks for the validation examples.
 *
 * <p>Not part of the SDK. The API returns the address IRS records hold, exactly
 * as they hold it; whether that address is good enough to mail a cheque to is a
 * customer decision.
 *
 * <p>The point of these checks is that a field being non-null is not the same as
 * a field being usable. A placeholder, a contradiction between components, or a
 * state code that disagrees with the spelled-out state all survive a null check
 * and none of them survive reading.
 */
public final class Addresses {

    /** Values that occupy a field without saying anything. */
    private static final Set<String> PLACEHOLDERS = new HashSet<>(Arrays.asList(
            "N/A", "NA", "NONE", "NULL", "UNKNOWN", "-", "."));

    /** The two-letter codes, paired with the names the API spells out. */
    private static final String[][] STATES = {
        {"AL", "ALABAMA"}, {"AK", "ALASKA"}, {"AZ", "ARIZONA"}, {"AR", "ARKANSAS"},
        {"CA", "CALIFORNIA"}, {"CO", "COLORADO"}, {"CT", "CONNECTICUT"}, {"DE", "DELAWARE"},
        {"DC", "DISTRICT OF COLUMBIA"}, {"FL", "FLORIDA"}, {"GA", "GEORGIA"}, {"HI", "HAWAII"},
        {"ID", "IDAHO"}, {"IL", "ILLINOIS"}, {"IN", "INDIANA"}, {"IA", "IOWA"},
        {"KS", "KANSAS"}, {"KY", "KENTUCKY"}, {"LA", "LOUISIANA"}, {"ME", "MAINE"},
        {"MD", "MARYLAND"}, {"MA", "MASSACHUSETTS"}, {"MI", "MICHIGAN"}, {"MN", "MINNESOTA"},
        {"MS", "MISSISSIPPI"}, {"MO", "MISSOURI"}, {"MT", "MONTANA"}, {"NE", "NEBRASKA"},
        {"NV", "NEVADA"}, {"NH", "NEW HAMPSHIRE"}, {"NJ", "NEW JERSEY"}, {"NM", "NEW MEXICO"},
        {"NY", "NEW YORK"}, {"NC", "NORTH CAROLINA"}, {"ND", "NORTH DAKOTA"}, {"OH", "OHIO"},
        {"OK", "OKLAHOMA"}, {"OR", "OREGON"}, {"PA", "PENNSYLVANIA"}, {"RI", "RHODE ISLAND"},
        {"SC", "SOUTH CAROLINA"}, {"SD", "SOUTH DAKOTA"}, {"TN", "TENNESSEE"}, {"TX", "TEXAS"},
        {"UT", "UTAH"}, {"VT", "VERMONT"}, {"VA", "VIRGINIA"}, {"WA", "WASHINGTON"},
        {"WV", "WEST VIRGINIA"}, {"WI", "WISCONSIN"}, {"WY", "WYOMING"}, {"PR", "PUERTO RICO"},
    };

    private Addresses() {
    }

    /**
     * Whether a value is a placeholder standing in for a real one.
     *
     * @param value the field value, or {@code null}.
     * @return true when the value occupies the field without filling it.
     */
    public static boolean isPlaceholder(String value) {
        return value != null && PLACEHOLDERS.contains(value.trim().toUpperCase(Locale.ROOT));
    }

    /**
     * The state name that goes with a two-letter code.
     *
     * @param code the code, or {@code null}.
     * @return the spelled-out name, or {@code null} when the code is unknown.
     */
    public static String stateName(String code) {
        if (code == null) {
            return null;
        }

        String needle = code.trim().toUpperCase(Locale.ROOT);

        for (String[] pair : STATES) {
            if (pair[0].equals(needle)) {
                return pair[1];
            }
        }

        return null;
    }

    /**
     * Everything questionable about the address on a record.
     *
     * <p>Reports observations, not a verdict: an address that produces findings
     * may still be perfectly mailable, and the caller decides.
     *
     * @param nonprofit the organization.
     * @return the findings, in the order they were checked. Empty when nothing
     *         looked wrong.
     */
    public static List<String> findings(Nonprofit nonprofit) {
        List<String> findings = new ArrayList<>();

        if (nonprofit.getAddressLine1() == null) {
            findings.add("address_line1 is null — there is no street address to use");
        }

        if (isPlaceholder(nonprofit.getAddressLine1())) {
            findings.add("address_line1 is a placeholder: \"" + nonprofit.getAddressLine1() + "\"");
        }

        if (isPlaceholder(nonprofit.getAddressLine2())) {
            findings.add("address_line2 is a placeholder: \"" + nonprofit.getAddressLine2() + "\"");
        }

        if (nonprofit.getZip() == null) {
            findings.add("zip is null — a mailing address without one is incomplete");
        }

        String expected = stateName(nonprofit.getState());

        if (expected != null
                && nonprofit.getStateName() != null
                && !expected.equalsIgnoreCase(nonprofit.getStateName().trim())) {
            findings.add("state \"" + nonprofit.getState() + "\" is " + expected
                    + ", but state_name says \"" + nonprofit.getStateName() + "\"");
        }

        if (nonprofit.getState() != null && expected == null) {
            findings.add("state \"" + nonprofit.getState() + "\" is not a code this table knows");
        }

        if (nonprofit.getPub78State() != null
                && nonprofit.getState() != null
                && !nonprofit.getPub78State().trim().equalsIgnoreCase(nonprofit.getState().trim())) {
            findings.add("the BMF address says " + nonprofit.getState()
                    + " and Publication 78 says " + nonprofit.getPub78State());
        }

        if (nonprofit.getPub78City() != null
                && nonprofit.getCity() != null
                && !nonprofit.getPub78City().trim().equalsIgnoreCase(nonprofit.getCity().trim())) {
            findings.add("the BMF address says " + nonprofit.getCity()
                    + " and Publication 78 says " + nonprofit.getPub78City());
        }

        return Collections.unmodifiableList(findings);
    }
}
