package org.pactman.nonprofitcheckplus.examples.support;

import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.Map;

/**
 * Local lookup tables for IRS codes the API returns without a description.
 *
 * <p>The API already describes most classifications for you —
 * {@code subsection_description}, {@code foundation_code_description},
 * {@code foundation_type_description}. Prefer those: they come from the source
 * and change with it. Only fields returned as a bare code need a table, and a
 * table you own is a table you have to maintain.
 *
 * <p>Two rules make that safe:
 *
 * <ol>
 *   <li>Every lookup has an unknown-value fallback that keeps the original code
 *       visible, so a value added by the IRS degrades to "code 42, meaning
 *       unknown to this application" rather than to {@code null} or a wrong label.
 *   <li>{@code null} is reported as {@code null}, never as an unknown code.
 * </ol>
 *
 * <p>Verify these against the current IRS Exempt Organizations Business Master
 * File data dictionary and Publication 78 documentation before relying on them
 * for a policy decision.
 */
public final class IrsCodes {

    /** IRS EO BMF {@code FILING_REQ_CD} — which annual return the organization files. */
    private static final Map<String, String> FILING_REQUIREMENT = filingRequirement();

    /** IRS EO BMF {@code STATUS} — the exempt status the IRS records. */
    private static final Map<String, String> EXEMPT_STATUS = exemptStatus();

    /** IRS Automatic Revocation of Exemption reason codes. */
    private static final Map<String, String> REVOCATION_CODE = revocationCode();

    /** Publication 78 deductibility indicator. */
    private static final Map<String, String> PUB78_INDICATOR = pub78Indicator();

    private IrsCodes() {
    }

    private static Map<String, String> filingRequirement() {
        Map<String, String> codes = new LinkedHashMap<>();
        codes.put("00", "No 990 return required");
        codes.put("01", "Form 990 or 990-EZ required");
        codes.put("02", "Form 990-N (e-Postcard) required");
        codes.put("03", "Group return");
        codes.put("04", "Form 990-BL required (black lung trust)");
        codes.put("06", "Not required to file (church)");
        codes.put("07", "Government 501(c)(1)");
        codes.put("13", "Not required to file (religious organization)");
        codes.put("14", "Not required to file (instrumentalities of states or political subdivisions)");

        return Collections.unmodifiableMap(codes);
    }

    private static Map<String, String> exemptStatus() {
        Map<String, String> codes = new LinkedHashMap<>();
        codes.put("01", "Unconditional exemption");
        codes.put("02", "Conditional exemption");
        codes.put("12", "Trust described in section 4947(a)(2)");
        codes.put("25", "Exemption automatically revoked for failure to file");

        return Collections.unmodifiableMap(codes);
    }

    private static Map<String, String> revocationCode() {
        Map<String, String> codes = new LinkedHashMap<>();
        codes.put("01", "Automatic revocation for failure to file for three consecutive years");

        return Collections.unmodifiableMap(codes);
    }

    private static Map<String, String> pub78Indicator() {
        Map<String, String> codes = new LinkedHashMap<>();
        codes.put("0", "Listed in Publication 78");
        codes.put("1", "Listed under a group ruling");

        return Collections.unmodifiableMap(codes);
    }

    /**
     * Describes an IRS filing requirement code.
     *
     * @param code the code as the API returned it, or {@code null}.
     * @return the description, {@code null}, or a form that keeps an unknown
     *         code visible.
     */
    public static String describeFilingRequirement(String code) {
        return describe(FILING_REQUIREMENT, code, "filing requirement");
    }

    /**
     * Describes an IRS exempt status code.
     *
     * @param code the code as the API returned it, or {@code null}.
     * @return the description, {@code null}, or a form that keeps an unknown
     *         code visible.
     */
    public static String describeExemptStatus(String code) {
        return describe(EXEMPT_STATUS, code, "exempt status");
    }

    /**
     * Describes an IRS automatic revocation code.
     *
     * @param code the code as the API returned it, or {@code null}.
     * @return the description, {@code null}, or a form that keeps an unknown
     *         code visible.
     */
    public static String describeRevocationCode(String code) {
        return describe(REVOCATION_CODE, code, "revocation");
    }

    /**
     * Describes a Publication 78 deductibility indicator.
     *
     * @param code the code as the API returned it, or {@code null}.
     * @return the description, {@code null}, or a form that keeps an unknown
     *         code visible.
     */
    public static String describePub78Indicator(String code) {
        return describe(PUB78_INDICATOR, code, "Publication 78 indicator");
    }

    private static String describe(Map<String, String> table, String code, String kind) {
        if (code == null) {
            // The API returned no value. Saying "unknown code" here would invent
            // a code the API never sent.
            return null;
        }

        String description = table.get(code.trim());

        return description != null
                ? description
                : kind + " code \"" + code + "\", meaning unknown to this application";
    }
}
