/**
 * Local lookup tables for IRS codes the API returns without a description.
 *
 * The API already describes most classifications for you —
 * `subsection_description`, `foundation_code_description`,
 * `foundation_type_description`. Prefer those: they come from the source and
 * change with it. Only fields returned as a bare code need a table, and a table
 * you own is a table you have to maintain.
 *
 * Two rules make that safe:
 *
 * 1. Every lookup has an unknown-value fallback that keeps the original code
 *    visible, so a value added by the IRS degrades to `code "42", meaning
 *    unknown to this application` rather than to `null` or a wrong label.
 * 2. `null` is reported as `null`, never as an unknown code.
 *
 * Verify these against the current IRS Exempt Organizations Business Master File
 * data dictionary and Publication 78 documentation before relying on them for a
 * policy decision.
 */
@IsTest
public class ExampleIrsCodes {
    /** IRS EO BMF `FILING_REQ_CD` — which annual return the organization files. */
    private static final Map<String, String> FILING_REQUIREMENT = new Map<String, String>{
        '00' => 'No 990 return required',
        '01' => 'Form 990 or 990-EZ required',
        '02' => 'Form 990-N (e-Postcard) required',
        '03' => 'Group return',
        '04' => 'Form 990-BL required (black lung trust)',
        '06' => 'Not required to file (church)',
        '07' => 'Government 501(c)(1)',
        '13' => 'Not required to file (religious organization)',
        '14' => 'Not required to file (instrumentalities of states or political subdivisions)'
    };

    /** IRS EO BMF `STATUS` — the exempt status the IRS records. */
    private static final Map<String, String> EXEMPT_STATUS = new Map<String, String>{
        '01' => 'Unconditional exemption',
        '02' => 'Conditional exemption',
        '12' => 'Trust described in section 4947(a)(2)',
        '25' => 'Exemption automatically revoked for failure to file'
    };

    /** IRS Automatic Revocation of Exemption reason codes. */
    private static final Map<String, String> REVOCATION_CODE = new Map<String, String>{
        '01' => 'Automatic revocation for failure to file for three consecutive years'
    };

    /** Publication 78 deductibility indicator. */
    private static final Map<String, String> PUB78_INDICATOR = new Map<String, String>{
        '0' => 'Listed in Publication 78',
        '1' => 'Listed under a group ruling'
    };

    /** Describes an IRS filing requirement code. */
    public static String describeFilingRequirement(String code) {
        return describe(FILING_REQUIREMENT, code, 'filing requirement');
    }

    /** Describes an IRS exempt status code. */
    public static String describeExemptStatus(String code) {
        return describe(EXEMPT_STATUS, code, 'exempt status');
    }

    /** Describes an IRS automatic revocation code. */
    public static String describeRevocationCode(String code) {
        return describe(REVOCATION_CODE, code, 'revocation');
    }

    /** Describes a Publication 78 deductibility indicator. */
    public static String describePub78Indicator(String code) {
        return describe(PUB78_INDICATOR, code, 'Publication 78 indicator');
    }

    private static String describe(Map<String, String> table, String code, String kind) {
        if (code == null) {
            // The API returned no value. Saying "unknown code" here would
            // invent a code the API never sent.
            return null;
        }

        String description = table.get(code.trim());

        return description != null
            ? description
            : kind + ' code "' + code + '", meaning unknown to this application';
    }
}
