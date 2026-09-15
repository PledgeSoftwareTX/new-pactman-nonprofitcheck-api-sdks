/**
 * Address checks for the validation examples.
 *
 * Not part of the SDK. The API returns the address IRS records hold, exactly as
 * they hold it; whether that address is good enough to mail a cheque to is a
 * customer decision.
 *
 * The point of these checks is that a field being non-null is not the same as a
 * field being usable. A placeholder, a contradiction between components, or a
 * state code that disagrees with the spelled-out state all survive a null check,
 * and none of them survive reading.
 */
@IsTest
public class ExampleAddresses {
    /** Values that occupy a field without saying anything. */
    private static final Set<String> PLACEHOLDERS = new Set<String>{
        'N/A', 'NA', 'NONE', 'NULL', 'UNKNOWN', '-', '.'
    };

    /** The two-letter codes, paired with the names the API spells out. */
    private static final Map<String, String> STATE_NAMES = new Map<String, String>{
        'AL' => 'ALABAMA', 'AK' => 'ALASKA', 'AZ' => 'ARIZONA', 'AR' => 'ARKANSAS',
        'CA' => 'CALIFORNIA', 'CO' => 'COLORADO', 'CT' => 'CONNECTICUT', 'DE' => 'DELAWARE',
        'DC' => 'DISTRICT OF COLUMBIA', 'FL' => 'FLORIDA', 'GA' => 'GEORGIA', 'HI' => 'HAWAII',
        'ID' => 'IDAHO', 'IL' => 'ILLINOIS', 'IN' => 'INDIANA', 'IA' => 'IOWA',
        'KS' => 'KANSAS', 'KY' => 'KENTUCKY', 'LA' => 'LOUISIANA', 'ME' => 'MAINE',
        'MD' => 'MARYLAND', 'MA' => 'MASSACHUSETTS', 'MI' => 'MICHIGAN', 'MN' => 'MINNESOTA',
        'MS' => 'MISSISSIPPI', 'MO' => 'MISSOURI', 'MT' => 'MONTANA', 'NE' => 'NEBRASKA',
        'NV' => 'NEVADA', 'NH' => 'NEW HAMPSHIRE', 'NJ' => 'NEW JERSEY', 'NM' => 'NEW MEXICO',
        'NY' => 'NEW YORK', 'NC' => 'NORTH CAROLINA', 'ND' => 'NORTH DAKOTA', 'OH' => 'OHIO',
        'OK' => 'OKLAHOMA', 'OR' => 'OREGON', 'PA' => 'PENNSYLVANIA', 'RI' => 'RHODE ISLAND',
        'SC' => 'SOUTH CAROLINA', 'SD' => 'SOUTH DAKOTA', 'TN' => 'TENNESSEE', 'TX' => 'TEXAS',
        'UT' => 'UTAH', 'VT' => 'VERMONT', 'VA' => 'VIRGINIA', 'WA' => 'WASHINGTON',
        'WV' => 'WEST VIRGINIA', 'WI' => 'WISCONSIN', 'WY' => 'WYOMING', 'PR' => 'PUERTO RICO'
    };

    /** True when a value occupies a field without filling it. */
    public static Boolean isPlaceholder(String value) {
        return value != null && PLACEHOLDERS.contains(value.trim().toUpperCase());
    }

    /** The spelled-out name for a two-letter code, or `null` when unknown. */
    public static String stateName(String code) {
        return code == null ? null : STATE_NAMES.get(code.trim().toUpperCase());
    }

    /**
     * Everything questionable about the address on a record.
     *
     * Reports observations, not a verdict: an address that produces findings may
     * still be perfectly mailable, and the caller decides.
     */
    public static List<String> findings(Nonprofit nonprofit) {
        List<String> findings = new List<String>();

        if (nonprofit.address_line1 == null) {
            findings.add('address_line1 is null - there is no street address to use');
        }

        if (isPlaceholder(nonprofit.address_line1)) {
            findings.add('address_line1 is a placeholder: "' + nonprofit.address_line1 + '"');
        }

        if (isPlaceholder(nonprofit.address_line2)) {
            findings.add('address_line2 is a placeholder: "' + nonprofit.address_line2 + '"');
        }

        if (nonprofit.zip == null) {
            findings.add('zip is null - a mailing address without one is incomplete');
        }

        String expected = stateName(nonprofit.state);

        if (
            expected != null &&
            nonprofit.state_name != null &&
            !expected.equalsIgnoreCase(nonprofit.state_name.trim())
        ) {
            findings.add(
                'state "' + nonprofit.state + '" is ' + expected +
                    ', but state_name says "' + nonprofit.state_name + '"'
            );
        }

        if (nonprofit.state != null && expected == null) {
            findings.add('state "' + nonprofit.state + '" is not a code this table knows');
        }

        if (
            nonprofit.pub78_state != null &&
            nonprofit.state != null &&
            !nonprofit.pub78_state.trim().equalsIgnoreCase(nonprofit.state.trim())
        ) {
            findings.add(
                'the BMF address says ' + nonprofit.state +
                    ' and Publication 78 says ' + nonprofit.pub78_state
            );
        }

        if (
            nonprofit.pub78_city != null &&
            nonprofit.city != null &&
            !nonprofit.pub78_city.trim().equalsIgnoreCase(nonprofit.city.trim())
        ) {
            findings.add(
                'the BMF address says ' + nonprofit.city +
                    ' and Publication 78 says ' + nonprofit.pub78_city
            );
        }

        return findings;
    }
}
