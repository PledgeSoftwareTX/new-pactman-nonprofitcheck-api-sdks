package org.pactman.nonprofitcheckplus.support;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.LinkedHashMap;
import java.util.Map;
import org.pactman.nonprofitcheckplus.PactmanClient;
import org.pactman.nonprofitcheckplus.config.PactmanClientOptions;
import org.pactman.nonprofitcheckplus.http.TransportHooks;
import org.pactman.nonprofitcheckplus.internal.Json;

/** Shared test data and client wiring. */
public final class Fixtures {

    /** A key that must never appear in any diagnostic output. */
    public static final String TEST_API_KEY = "pactman_test_key_do_not_leak_8f2b";

    /** The base URL the stubbed clients point at. */
    public static final String BASE_URL = "http://mock.test";

    private Fixtures() {
    }

    /**
     * A client wired to a stub exchange.
     *
     * @param exchange the exchange to send through.
     * @return the client.
     */
    public static PactmanClient client(StubExchange exchange) {
        return client(exchange, null);
    }

    /**
     * A client wired to a stub exchange and a recording clock.
     *
     * @param exchange the exchange to send through.
     * @param hooks    the clock and random source, or {@code null} for the real ones.
     * @return the client.
     */
    public static PactmanClient client(StubExchange exchange, TransportHooks hooks) {
        return new PactmanClient(
                PactmanClientOptions.builder()
                        .apiKey(TEST_API_KEY)
                        .baseUrl(BASE_URL)
                        .httpExchange(exchange)
                        .build(),
                hooks);
    }

    /**
     * A representative organization, mirroring the published response example.
     *
     * @return the organization's fields, mutable so a test can vary one.
     */
    public static Map<String, Object> nonprofit() {
        Map<String, Object> organization = new LinkedHashMap<>();
        organization.put(
                "pactman_org_url",
                "https://pactman.org/profile/nonprofit/example-nonprofit-r5U9r8yRcZ");
        organization.put("organization_info_last_modified", "2/22/2026 1:16:30 AM");
        organization.put("ein", "411787097");
        organization.put("organization_name", "EXAMPLE NONPROFIT");
        organization.put("organization_name_aka", "EXAMPLE N.P");
        organization.put("address_line1", "50 LOWELL AVE");
        organization.put("address_line2", "APT 3B");
        organization.put("city", "WESTFIELD");
        organization.put("state", "MA");
        organization.put("state_name", "Massachusetts");
        organization.put("zip", "01085-2643");
        organization.put("filing_req_code", "00");
        organization.put("pub78_church_message", null);
        organization.put("pub78_organization_name", "Example Nonprofit");
        organization.put("pub78_ein", "411787097");
        organization.put("pub78_verified", Boolean.TRUE);
        organization.put("pub78_city", "Westfield");
        organization.put("pub78_state", "MA");
        organization.put("pub78_indicator", "0");

        Map<String, Object> organizationType = new LinkedHashMap<>();
        organizationType.put(
                "organization_type",
                "Deductions for donations to public charities are generally limited...");
        organizationType.put("deductibility_limitation", "50%");
        organizationType.put("deductibility_status_description", "PC");
        organization.put("organization_types", new ArrayList<>(Arrays.asList(organizationType)));

        organization.put("most_recent_pub78", "12/12/2025 12:00:00 AM");
        organization.put("bmf_church_message", null);
        organization.put("bmf_organization_name", "EXAMPLE NONPROFIT");
        organization.put("bmf_ein", "411787097");
        organization.put("bmf_status", Boolean.TRUE);
        organization.put("most_recent_bmf", "12/09/2025 12:00:00 AM");
        organization.put("bmf_subsection", "03");
        organization.put("subsection_description", "501(c)(3) Public Charity");
        organization.put("foundation_code", "10");
        organization.put(
                "foundation_code_description",
                "Public charity described in section 509(a)(1) or (2)");
        organization.put("ruling_month", "07");
        organization.put("ruling_year", "2024");
        organization.put("group_exemption", "0000");
        organization.put("exempt_status_code", "01");
        organization.put(
                "ofac_status",
                "This organization was NOT included in the Office of Foreign Assets Control "
                        + "Specially Designated Nationals (SDN) list.");
        organization.put("revocation_code", null);
        organization.put("revocation_date", null);
        organization.put("reinstatement_date", null);
        organization.put("irs_bmf_pub78_conflict", Boolean.FALSE);
        organization.put("foundation_509a_status", "N/A");
        organization.put("report_date", "3/25/2026 3:28:54 PM");
        organization.put("foundation_type_code", "pc");
        organization.put(
                "foundation_type_description",
                "Public charity described in section 509(a)(1) or (2)");

        return organization;
    }

    /**
     * The representative organization with fields replaced.
     *
     * @param overrides field names and values to set, in pairs.
     * @return the organization's fields.
     */
    public static Map<String, Object> nonprofit(Object... overrides) {
        Map<String, Object> organization = nonprofit();

        for (int i = 0; i + 1 < overrides.length; i += 2) {
            organization.put((String) overrides[i], overrides[i + 1]);
        }

        return organization;
    }

    /**
     * Wraps a payload in the envelope the API returns.
     *
     * @param data      the payload.
     * @param overrides envelope fields to replace, in pairs.
     * @return the envelope's fields.
     */
    public static Map<String, Object> envelope(Object data, Object... overrides) {
        Map<String, Object> envelope = new LinkedHashMap<>();
        envelope.put("code", 200L);
        envelope.put("message", "OK");
        envelope.put("errors", null);
        envelope.put("data", data);
        envelope.put("timeTaken", 3L);
        envelope.put("nonprofit_check_count", 1L);

        for (int i = 0; i + 1 < overrides.length; i += 2) {
            envelope.put((String) overrides[i], overrides[i + 1]);
        }

        return envelope;
    }

    /**
     * Serializes a value as JSON.
     *
     * @param value the value.
     * @return the JSON text.
     */
    public static String json(Object value) {
        return Json.write(value);
    }

    /**
     * Parses JSON.
     *
     * @param text the JSON text.
     * @return the decoded value.
     */
    public static Object parse(String text) {
        return Json.parse(text);
    }
}
