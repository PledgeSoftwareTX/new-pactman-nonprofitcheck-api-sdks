package org.pactman.nonprofitcheckplus;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.pactman.nonprofitcheckplus.support.Fixtures.BASE_URL;
import static org.pactman.nonprofitcheckplus.support.Fixtures.TEST_API_KEY;
import static org.pactman.nonprofitcheckplus.support.Fixtures.client;
import static org.pactman.nonprofitcheckplus.support.Fixtures.envelope;
import static org.pactman.nonprofitcheckplus.support.Fixtures.json;
import static org.pactman.nonprofitcheckplus.support.Fixtures.nonprofit;

import java.util.Map;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.pactman.nonprofitcheckplus.exceptions.PactmanValidationException;
import org.pactman.nonprofitcheckplus.models.Nonprofit;
import org.pactman.nonprofitcheckplus.models.SingleCheckResult;
import org.pactman.nonprofitcheckplus.support.RecordedRequest;
import org.pactman.nonprofitcheckplus.support.StubExchange;
import org.pactman.nonprofitcheckplus.support.StubResponse;

class CheckTest {

    @Test
    @DisplayName("sends exactly one authenticated request and returns a deserialized model")
    void sendsOneAuthenticatedRequest() {
        StubExchange exchange = StubExchange.serving(json(envelope(nonprofit())));
        SingleCheckResult result = client(exchange).nonprofits().check("411787097");

        assertEquals(1, exchange.callCount());

        RecordedRequest request = exchange.request(0);
        assertEquals("GET", request.method());
        assertEquals(
                BASE_URL + "/api/entities/nonprofitcheck/v1/us/ein/411787097",
                request.uri().toString());
        assertEquals("Bearer " + TEST_API_KEY, request.header("authorization"));
        assertEquals("application/json", request.header("accept"));
        assertTrue(request.header("user-agent").startsWith(SdkVersion.PACKAGE_NAME));

        assertEquals("EXAMPLE NONPROFIT", result.getNonprofit().getOrganizationName());
        assertEquals("411787097", result.getNonprofit().getEin());
    }

    @Test
    @DisplayName("normalizes a hyphenated EIN before building the URL")
    void normalizesHyphenatedEin() {
        StubExchange exchange = StubExchange.serving(json(envelope(nonprofit())));
        client(exchange).nonprofits().check("41-1787097");

        assertTrue(exchange.request(0).uri().toString().endsWith("/us/ein/411787097"));
    }

    @Test
    @DisplayName("maps usage information from the envelope")
    void mapsUsageInformation() {
        StubExchange exchange = StubExchange.serving(
                json(envelope(nonprofit(), "nonprofit_check_count", 7L, "timeTaken", 42L)));
        SingleCheckResult result = client(exchange).nonprofits().check("411787097");

        assertEquals(Integer.valueOf(7), result.getCheckCount());
        assertEquals(Double.valueOf(42), result.getTimeTakenMs());
        assertEquals(200, result.getStatus());
    }

    @Test
    @DisplayName("preserves null and false as distinct values")
    void preservesNullAndFalse() {
        Map<String, Object> organization = nonprofit(
                "pub78_verified", Boolean.FALSE,
                "bmf_status", null,
                "revocation_code", null,
                "irs_bmf_pub78_conflict", Boolean.FALSE);
        StubExchange exchange = StubExchange.serving(json(envelope(organization)));

        Nonprofit found = client(exchange).nonprofits().check("411787097").getNonprofit();

        assertEquals(Boolean.FALSE, found.getPub78Verified());
        assertNull(found.getBmfStatus());
        assertTrue(found.has("bmf_status"), "a field returned as null is still a field it returned");
        assertNull(found.getRevocationCode());
        assertEquals(Boolean.FALSE, found.getIrsBmfPub78Conflict());
        assertTrue(found.getOfacStatus().contains("NOT included"));
    }

    @Test
    @DisplayName("distinguishes an absent field from one returned as null")
    void distinguishesAbsentFromNull() {
        Map<String, Object> organization = nonprofit();
        organization.remove("bmf_status");
        StubExchange exchange = StubExchange.serving(json(envelope(organization)));

        Nonprofit found = client(exchange).nonprofits().check("411787097").getNonprofit();

        assertFalse(found.has("bmf_status"));
        assertNull(found.getBmfStatus());
    }

    @Test
    @DisplayName("keeps unknown future fields readable through the raw response")
    void keepsUnknownFieldsReadable() {
        Map<String, Object> envelope = envelope(
                nonprofit("future_source_status", "listed"),
                "future_envelope_field", java.util.Collections.singletonMap("nested", Boolean.TRUE));
        StubExchange exchange = StubExchange.serving(json(envelope));

        SingleCheckResult result = client(exchange).nonprofits().check("411787097");

        assertEquals("EXAMPLE NONPROFIT", result.getNonprofit().getOrganizationName());
        assertEquals("listed", result.getNonprofit().get("future_source_status"));
        assertEquals(
                Boolean.TRUE,
                result.getRaw().getMap("future_envelope_field").get("nested"));
    }

    @Test
    @DisplayName("returns null rather than throwing when data is absent")
    void returnsNullWhenDataAbsent() {
        StubExchange exchange =
                StubExchange.serving(json(envelope(null, "nonprofit_check_count", 0L)));
        SingleCheckResult result = client(exchange).nonprofits().check("411787097");

        assertNull(result.getNonprofit());
        assertEquals(Integer.valueOf(0), result.getCheckCount());
    }

    @Test
    @DisplayName("reads an organization the API wrapped in a single-element array")
    void readsOrganizationFromArray() {
        StubExchange exchange = StubExchange.serving(
                json(envelope(java.util.Collections.singletonList(nonprofit()))));

        SingleCheckResult result = client(exchange).nonprofits().check("411787097");

        assertNotNull(result.getNonprofit());
        assertEquals("411787097", result.getNonprofit().getEin());
    }

    @Test
    @DisplayName("fails locally on a malformed EIN without sending a request")
    void failsLocallyOnMalformedEin() {
        StubExchange exchange = StubExchange.serving(json(envelope(nonprofit())));

        assertThrows(
                PactmanValidationException.class,
                () -> client(exchange).nonprofits().check("41178709"));
        assertEquals(0, exchange.callCount());
    }

    @Test
    @DisplayName("treats an empty body as an empty envelope rather than failing")
    void treatsEmptyBodyAsEmptyEnvelope() {
        StubExchange exchange = new StubExchange(StubResponse.empty(200));

        SingleCheckResult result = client(exchange).nonprofits().check("411787097");

        assertNull(result.getNonprofit());
        assertNull(result.getCheckCount());
        assertEquals(0, result.getErrors().size());
    }

    @Test
    @DisplayName("reads the correlation id from any header the gateway may use")
    void readsCorrelationId() {
        StubExchange exchange = new StubExchange(
                StubResponse.json(json(envelope(nonprofit()))).header("x-correlation-id", "abc-123"));

        SingleCheckResult result = client(exchange).nonprofits().check("411787097");

        assertEquals("abc-123", result.getRequestId());
    }
}
