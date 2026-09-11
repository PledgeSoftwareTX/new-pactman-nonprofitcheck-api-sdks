package org.pactman.nonprofitcheckplus.devtools;

import java.io.IOException;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import org.pactman.nonprofitcheckplus.internal.Json;

/**
 * Fixture organizations for the examples and the fixture API.
 *
 * <p>Scenarios like a revoked exemption, an OFAC match, a cross-source conflict
 * or an unknown future field cannot be summoned on demand from the production
 * API. They are declared here once so an example can demonstrate the handling
 * and the fixture server can serve the record.
 *
 * <p>Field names and values mirror the shapes documented in the Pactman API
 * reference. The EINs are illustrative and are not real organizations.
 */
public final class Fixtures {

    /** The two OFAC sentences the API returns. It reports prose, not a boolean. */
    public static final String OFAC_NO_MATCH =
            "This organization was NOT included in the Office of Foreign Assets Control "
                    + "Specially Designated Nationals (SDN) list.";

    /** The wording the API uses when it found a possible SDN match. */
    public static final String OFAC_POSSIBLE_MATCH =
            "This organization may be included in the Office of Foreign Assets Control "
                    + "Specially Designated Nationals(SDN) list. A close match was found with "
                    + "the Special Designated National with UID: 41234";

    private static final Map<String, Map<String, Object>> ORGANIZATIONS = build();

    private Fixtures() {
    }

    /**
     * Whether the fixture API has a record for this EIN.
     *
     * @param ein the normalized EIN.
     * @return whether a record exists.
     */
    public static boolean has(String ein) {
        return ORGANIZATIONS.containsKey(ein);
    }

    /**
     * The record for an EIN.
     *
     * @param ein the normalized EIN.
     * @return a fresh copy of the record, or {@code null} when there is none.
     */
    public static Map<String, Object> organization(String ein) {
        Map<String, Object> found = ORGANIZATIONS.get(ein);

        return found == null ? null : new LinkedHashMap<>(found);
    }

    /**
     * Every field this package predicts on an organization.
     *
     * <p>Read from {@code response-contract.json} rather than from a fixture, so
     * that what the SDK claims to know is stated in one place. A fixture is an
     * example of a record; the contract is the promise, and the promise is what
     * drift is measured against. A field outside this set is newer than this
     * SDK, which is not an error, but is worth knowing about.
     *
     * @return the predicted field names.
     */
    @SuppressWarnings("unchecked")
    public static Set<String> knownNonprofitFields() {
        try (InputStream stream = Fixtures.class.getResourceAsStream(
                "/org/pactman/nonprofitcheckplus/response-contract.json")) {
            StringBuilder text = new StringBuilder();
            char[] buffer = new char[8192];

            try (InputStreamReader reader =
                    new InputStreamReader(stream, StandardCharsets.UTF_8)) {
                int read;

                while ((read = reader.read(buffer)) != -1) {
                    text.append(buffer, 0, read);
                }
            }

            Map<String, Object> contract = (Map<String, Object>) Json.parse(text.toString());

            return Collections.unmodifiableSet(new LinkedHashSet<>(
                    ((Map<String, Object>) contract.get("nonprofit")).keySet()));
        } catch (IOException unreadable) {
            throw new IllegalStateException("response-contract.json is not readable", unreadable);
        }
    }

    private static Map<String, Object> deductibility(
            String text, String limitation, String status) {
        Map<String, Object> entry = new LinkedHashMap<>();
        entry.put("organization_type", text);
        entry.put("deductibility_limitation", limitation);
        entry.put("deductibility_status_description", status);

        return entry;
    }

    private static Map<String, Object> publicCharityDeductibility() {
        return deductibility(
                "Deductions for donations to public charities are generally limited to 50 "
                        + "percent of adjusted gross income (AGI). This limit increases to 60% "
                        + "of AGI for cash donations. For Non-Cash assets held for more than one "
                        + "year, the limit is 30% of AGI.",
                "50%",
                "PC");
    }

    private static Map<String, Object> privateFoundationDeductibility() {
        return deductibility(
                "Deductions for donations to private foundations are generally limited to 30 "
                        + "percent of adjusted gross income (AGI). For Non-Cash assets held for "
                        + "more than one year, the limit is 20% of AGI.",
                "30%",
                "PF");
    }

    private static String slug(String name) {
        return name.toLowerCase(Locale.ROOT).replaceAll("[^a-z0-9]+", "-")
                .replaceAll("^-|-$", "");
    }

    /** A complete, unremarkable public charity. Scenarios override from here. */
    private static Map<String, Object> publicCharity(String ein, String name) {
        Map<String, Object> organization = new LinkedHashMap<>();
        organization.put(
                "pactman_org_url",
                "https://pactman.org/profile/nonprofit/" + slug(name) + "-"
                        + ein.substring(ein.length() - 4));
        organization.put("organization_info_last_modified", ApiDate.daysAgo(40));

        organization.put("ein", ein);
        organization.put("organization_name", name.toUpperCase(Locale.ROOT));
        organization.put("organization_name_aka", null);
        organization.put("address_line1", "50 LOWELL AVE");
        organization.put("address_line2", "APT 3B");
        organization.put("city", "WESTFIELD");
        organization.put("state", "MA");
        organization.put("state_name", "Massachusetts");
        organization.put("zip", "01085-2643");
        organization.put("filing_req_code", "01");

        organization.put("pub78_church_message", null);
        organization.put("pub78_organization_name", name);
        organization.put("pub78_ein", ein);
        organization.put("pub78_verified", Boolean.TRUE);
        organization.put("pub78_city", "Westfield");
        organization.put("pub78_state", "MA");
        organization.put("pub78_indicator", "0");
        organization.put(
                "organization_types",
                new ArrayList<>(Arrays.asList(publicCharityDeductibility())));
        organization.put("most_recent_pub78", ApiDate.daysAgo(26));

        organization.put("bmf_church_message", null);
        organization.put("bmf_organization_name", name.toUpperCase(Locale.ROOT));
        organization.put("bmf_ein", ein);
        organization.put("bmf_status", Boolean.TRUE);
        organization.put("bmf_subsection", "03");
        organization.put("most_recent_bmf", ApiDate.daysAgo(20));
        organization.put("subsection_description", "501(c)(3) Public Charity");
        organization.put("foundation_code", "10");
        organization.put(
                "foundation_code_description",
                "Public charity described in section 509(a)(1) or (2)");
        organization.put("foundation_type_code", "pc");
        organization.put(
                "foundation_type_description",
                "Public charity described in section 509(a)(1) or (2)");
        organization.put("foundation_509a_status", "N/A");
        organization.put("ruling_month", "07");
        organization.put("ruling_year", "2024");
        organization.put("group_exemption", "0000");
        organization.put("exempt_status_code", "01");

        organization.put("ofac_status", OFAC_NO_MATCH);

        organization.put("revocation_code", null);
        organization.put("revocation_date", null);
        organization.put("reinstatement_date", null);

        organization.put("irs_bmf_pub78_conflict", Boolean.FALSE);
        organization.put("report_date", ApiDate.daysAgo(0));

        return organization;
    }

    private static Map<String, Map<String, Object>> build() {
        Map<String, Map<String, Object>> all = new LinkedHashMap<>();

        Map<String, Object> charity =
                publicCharity(FixtureEins.PUBLIC_CHARITY, "Meals Today Example Nonprofit");
        charity.put("organization_name_aka", "MEALS TODAY E.N");
        charity.put("pub78_organization_name", "Meals Today Example Nonprofit, Inc.");
        all.put(FixtureEins.PUBLIC_CHARITY, charity);

        Map<String, Object> second =
                publicCharity(FixtureEins.PUBLIC_CHARITY_SECOND, "Aborjaily Example Nonprofit");
        second.put("organization_name_aka", "ABORJAILY E.N");
        second.put("city", "SPRINGFIELD");
        second.put("pub78_city", "Springfield");
        second.put("zip", "01103-1420");
        second.put("address_line1", "19 HAMPDEN ST");
        second.put("address_line2", null);
        all.put(FixtureEins.PUBLIC_CHARITY_SECOND, second);

        Map<String, Object> foundation = publicCharity(
                FixtureEins.PRIVATE_FOUNDATION, "Hartwell Family Example Foundation");
        // A private foundation files a 990-PF, so it carries no general 990
        // filing requirement.
        foundation.put("filing_req_code", "00");
        foundation.put(
                "organization_types",
                new ArrayList<>(Arrays.asList(privateFoundationDeductibility())));
        foundation.put("subsection_description", "501(c)(3) Private Foundation");
        foundation.put("foundation_code", "04");
        foundation.put("foundation_code_description", "Private non-operating foundation");
        foundation.put("foundation_type_code", "pf");
        foundation.put("foundation_type_description", "Private non-operating foundation");
        foundation.put("ruling_month", "11");
        foundation.put("ruling_year", "1998");
        all.put(FixtureEins.PRIVATE_FOUNDATION, foundation);

        // Optional identity fields the API had no value for. `null` here means
        // "the API returned no value", which is not the same as "this did not
        // match".
        Map<String, Object> sparse =
                publicCharity(FixtureEins.SPARSE_IDENTITY, "Quiet Harbor Example Trust");
        sparse.put("address_line1", "PO BOX 118");
        sparse.put("address_line2", null);
        sparse.put("city", "ROCKPORT");
        sparse.put("state", "ME");
        sparse.put("state_name", null);
        sparse.put("zip", null);
        sparse.put("pub78_city", null);
        sparse.put("pub78_state", null);
        sparse.put("group_exemption", null);
        sparse.put("ruling_month", null);
        sparse.put("ruling_year", null);
        // No OFAC key at all: the source was not reported for this organization,
        // which is not the same as a null status or a no-match result.
        sparse.remove("ofac_status");
        all.put(FixtureEins.SPARSE_IDENTITY, sparse);

        // Every address component is present, and they contradict one another:
        // the state code says Massachusetts, the state name and the ZIP say
        // Maine, and address_line2 holds a placeholder. Transcription damage of
        // this kind survives any check that only asks whether a field came back
        // non-null.
        Map<String, Object> inconsistent = publicCharity(
                FixtureEins.INCONSISTENT_ADDRESS, "Harbor Light Example Alliance");
        inconsistent.put("address_line1", "12 SEA STREET");
        inconsistent.put("address_line2", "N/A");
        inconsistent.put("city", "ROCKPORT");
        inconsistent.put("state", "MA");
        inconsistent.put("state_name", "Maine");
        inconsistent.put("zip", "04856");
        inconsistent.put("pub78_city", "Rockport");
        inconsistent.put("pub78_state", "MA");
        all.put(FixtureEins.INCONSISTENT_ADDRESS, inconsistent);

        // Nothing adverse, but every source is well out of date. A workflow with
        // a re-review rule should notice this even though the findings look clean.
        Map<String, Object> stale =
                publicCharity(FixtureEins.STALE_DATA, "Long Quiet Example Foundation");
        stale.put("organization_info_last_modified", ApiDate.daysAgo(700));
        stale.put("most_recent_pub78", ApiDate.daysAgo(640));
        stale.put("most_recent_bmf", ApiDate.daysAgo(610));
        all.put(FixtureEins.STALE_DATA, stale);

        Map<String, Object> revoked =
                publicCharity(FixtureEins.REVOKED, "Lapsed Filings Example Society");
        revoked.put("pub78_verified", Boolean.FALSE);
        revoked.put("pub78_indicator", null);
        revoked.put("organization_types", null);
        revoked.put("bmf_status", Boolean.FALSE);
        revoked.put("exempt_status_code", "25");
        revoked.put("revocation_code", "01");
        revoked.put("revocation_date", ApiDate.daysAgo(1_260));
        revoked.put("reinstatement_date", null);
        all.put(FixtureEins.REVOKED, revoked);

        Map<String, Object> reinstated =
                publicCharity(FixtureEins.REINSTATED, "Second Chance Example Alliance");
        reinstated.put("organization_name_aka", "SECOND CHANCE E.A");
        reinstated.put("revocation_code", "01");
        reinstated.put("revocation_date", ApiDate.daysAgo(1_260));
        reinstated.put("reinstatement_date", ApiDate.daysAgo(520));
        all.put(FixtureEins.REINSTATED, reinstated);

        Map<String, Object> ofacMatch =
                publicCharity(FixtureEins.OFAC_MATCH, "Overseas Relief Example Fund");
        ofacMatch.put("organization_name_aka", "OVERSEAS RELIEF E.F");
        ofacMatch.put("ofac_status", OFAC_POSSIBLE_MATCH);
        all.put(FixtureEins.OFAC_MATCH, ofacMatch);

        // The API returned nothing for OFAC. Absent is not the same as "no match".
        Map<String, Object> ofacUnavailable =
                publicCharity(FixtureEins.OFAC_UNAVAILABLE, "Riverbend Example Coalition");
        ofacUnavailable.put("ofac_status", null);
        all.put(FixtureEins.OFAC_UNAVAILABLE, ofacUnavailable);

        // BMF says exempt, Publication 78 does not list the organization, and
        // the API flags the disagreement rather than picking a winner.
        Map<String, Object> conflicted =
                publicCharity(FixtureEins.CONFLICTED, "Crosscheck Example Institute");
        conflicted.put("pub78_organization_name", null);
        conflicted.put("pub78_ein", null);
        conflicted.put("pub78_verified", Boolean.FALSE);
        conflicted.put("pub78_city", null);
        conflicted.put("pub78_state", null);
        conflicted.put("pub78_indicator", null);
        conflicted.put("organization_types", null);
        conflicted.put("bmf_organization_name", "CROSSCHECK EXAMPLE INST");
        conflicted.put("bmf_status", Boolean.TRUE);
        conflicted.put("irs_bmf_pub78_conflict", Boolean.TRUE);
        all.put(FixtureEins.CONFLICTED, conflicted);

        // A response from a newer API version: fields this SDK has never heard
        // of, and an enum value outside the documented set.
        Map<String, Object> future =
                publicCharity(FixtureEins.FUTURE_FIELDS, "Forward Compatible Example Trust");
        future.put("foundation_type_code", "zz");
        future.put(
                "foundation_type_description",
                "A classification added after this SDK was published");

        Map<String, Object> futureType = publicCharityDeductibility();
        futureType.put("deductibility_status_description", "XX");
        futureType.put("future_deductibility_note", "An unknown member of a known object");
        future.put("organization_types", new ArrayList<>(Arrays.asList(futureType)));

        future.put("state_charity_registration_status", "ACTIVE");

        Map<String, Object> screening = new LinkedHashMap<>();
        screening.put("provider", "example");
        screening.put("matches", 0L);
        screening.put("list_published_date", ApiDate.daysAgo(5));
        future.put("watchlist_screening", screening);
        all.put(FixtureEins.FUTURE_FIELDS, future);

        // A deployment running ahead of production. Every other fixture is the
        // shape entities.pactman.org returns today; this one adds the ten source
        // fields that are built but not yet released there. This package
        // deliberately does not declare them, so they exercise the path that
        // keeps undeclared fields readable through the raw response and
        // `get(...)` instead of dropping them.
        Map<String, Object> pending = publicCharity(
                FixtureEins.PENDING_SOURCE_FIELDS, "Ahead Of Production Example Fund");
        pending.put("pub78_source_org_type_1", "PC");
        pending.put("pub78_source_org_type_2", null);
        pending.put("pub78_source_org_type_3", null);
        pending.put("bmf_city", "WESTFIELD");
        pending.put("bmf_state", "MA");
        pending.put("bmf_street_address", "50 LOWELL AVE APT 3B");
        pending.put("bmf_source_pf_filing_req_cd", "0");
        pending.put("bmf_deductability_text", "Contributions are deductible");
        pending.put("ofac_list_published_date", ApiDate.daysAgo(5));
        pending.put("aroe_list_published_date", ApiDate.daysAgo(12));
        all.put(FixtureEins.PENDING_SOURCE_FIELDS, pending);

        return Collections.unmodifiableMap(all);
    }

    /**
     * Every fixture EIN that has a record, in declaration order.
     *
     * @return the EINs.
     */
    public static List<String> eins() {
        return Collections.unmodifiableList(new ArrayList<>(ORGANIZATIONS.keySet()));
    }
}
