package org.pactman.nonprofitcheckplus;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.pactman.nonprofitcheckplus.support.Fixtures.BASE_URL;
import static org.pactman.nonprofitcheckplus.support.Fixtures.client;
import static org.pactman.nonprofitcheckplus.support.Fixtures.envelope;
import static org.pactman.nonprofitcheckplus.support.Fixtures.json;
import static org.pactman.nonprofitcheckplus.support.Fixtures.nonprofit;
import static org.pactman.nonprofitcheckplus.support.Fixtures.parse;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.pactman.nonprofitcheckplus.config.BulkRequestOptions;
import org.pactman.nonprofitcheckplus.exceptions.PactmanValidationException;
import org.pactman.nonprofitcheckplus.models.BulkCheckResult;
import org.pactman.nonprofitcheckplus.support.RecordedRequest;
import org.pactman.nonprofitcheckplus.support.StubExchange;

class BulkTest {

    private static List<String> eins(String... values) {
        return new ArrayList<>(Arrays.asList(values));
    }

    private static String emptyBulk() {
        return json(envelope(new ArrayList<>()));
    }

    @Test
    @DisplayName("sends one request with a bare JSON array of normalized EINs")
    void sendsBareArrayOfNormalizedEins() {
        StubExchange exchange = StubExchange.serving(
                json(envelope(Arrays.asList(nonprofit(), nonprofit("ein", "996589560")))));

        BulkCheckResult result =
                client(exchange).nonprofits().checkBulk(eins("41-1787097", "996589560"));

        assertEquals(1, exchange.callCount());

        RecordedRequest request = exchange.request(0);
        assertEquals("POST", request.method());
        assertEquals(
                BASE_URL + "/api/entities/nonprofitcheckbulk/v1/us/eins",
                request.uri().toString());
        assertEquals("application/json", request.header("content-type"));
        assertEquals(Arrays.asList("411787097", "996589560"), parse(request.body()));

        assertEquals(2, result.getOrganizations().size());
        assertEquals("996589560", result.getOrganizations().get(1).getEin());
    }

    @Test
    @DisplayName("preserves input order and duplicates by default")
    void preservesOrderAndDuplicates() {
        StubExchange exchange = StubExchange.serving(emptyBulk());

        client(exchange).nonprofits().checkBulk(eins("996589560", "41-1787097", "996589560"));

        assertEquals(
                Arrays.asList("996589560", "411787097", "996589560"),
                parse(exchange.request(0).body()));
    }

    @Test
    @DisplayName("removes duplicates only when dedupe is requested")
    void dedupesOnlyWhenAsked() {
        StubExchange exchange = StubExchange.serving(emptyBulk());

        client(exchange).nonprofits().checkBulk(
                eins("996589560", "996589560", "41-1787097"),
                new BulkRequestOptions().dedupe(true));

        assertEquals(
                Arrays.asList("996589560", "411787097"), parse(exchange.request(0).body()));
    }

    @Test
    @DisplayName("rejects an empty collection locally")
    void rejectsEmptyCollection() {
        StubExchange exchange = StubExchange.serving(emptyBulk());

        assertThrows(
                PactmanValidationException.class,
                () -> client(exchange).nonprofits().checkBulk(Collections.<String>emptyList()));
        assertEquals(0, exchange.callCount());
    }

    @Test
    @DisplayName("rejects a null collection locally")
    void rejectsNullCollection() {
        StubExchange exchange = StubExchange.serving(emptyBulk());

        assertThrows(
                PactmanValidationException.class,
                () -> client(exchange).nonprofits().checkBulk(null));
        assertEquals(0, exchange.callCount());
    }

    @Test
    @DisplayName("rejects the whole batch when one EIN is malformed, before sending")
    void rejectsBatchWithOneMalformedEin() {
        StubExchange exchange = StubExchange.serving(emptyBulk());

        PactmanValidationException failure = assertThrows(
                PactmanValidationException.class,
                () -> client(exchange).nonprofits().checkBulk(eins("411787097", "not-an-ein")));

        assertEquals(1, failure.issues().size());
        assertEquals(Integer.valueOf(1), failure.issues().get(0).index());
        assertEquals(0, exchange.callCount());
    }

    @Test
    @DisplayName("enforces the server batch limit locally, from a single constant")
    void enforcesBatchLimit() {
        StubExchange exchange = StubExchange.serving(emptyBulk());
        List<String> tooMany = new ArrayList<>();

        for (int i = 0; i <= Endpoints.MAX_BULK_EINS; i++) {
            tooMany.add("411787097");
        }

        PactmanValidationException failure = assertThrows(
                PactmanValidationException.class,
                () -> client(exchange).nonprofits().checkBulk(tooMany));

        assertTrue(failure.getMessage().contains("at most " + Endpoints.MAX_BULK_EINS + " EINs"));
        assertEquals(0, exchange.callCount());
    }

    @Test
    @DisplayName("accepts exactly the batch limit")
    void acceptsExactlyTheLimit() {
        StubExchange exchange = StubExchange.serving(emptyBulk());
        List<String> atLimit = new ArrayList<>();

        for (int i = 0; i < Endpoints.MAX_BULK_EINS; i++) {
            atLimit.add("411787097");
        }

        client(exchange).nonprofits().checkBulk(atLimit);

        assertEquals(1, exchange.callCount());
    }

    @Test
    @DisplayName("surfaces per-item not-found results from a successful response")
    void surfacesNotFoundEins() {
        Map<String, Object> detail = new LinkedHashMap<>();
        detail.put("resource", "nonprofitcheckbulk");
        detail.put(
                "reason", "There are no matching nonprofits in our records for this set of EINs");
        detail.put("code", 404L);
        detail.put("eins", Collections.singletonList("996589560"));

        StubExchange exchange = StubExchange.serving(json(envelope(
                Collections.singletonList(nonprofit()),
                "nonprofit_check_count", 1L,
                "errors", Collections.singletonList(detail))));

        BulkCheckResult result =
                client(exchange).nonprofits().checkBulk(eins("411787097", "996589560"));

        assertEquals(1, result.getOrganizations().size());
        assertEquals(Collections.singletonList("996589560"), result.getNotFoundEins());
        assertEquals(Integer.valueOf(404), result.getErrors().get(0).getCode());
        assertEquals(Integer.valueOf(1), result.getCheckCount());
    }

    @Test
    @DisplayName("reads not-found EINs the API sent as a comma-separated string")
    void readsNotFoundEinsFromString() {
        Map<String, Object> detail = new LinkedHashMap<>();
        detail.put("reason", "no matching nonprofits");
        detail.put("eins", "996589560, 411787098");

        StubExchange exchange = StubExchange.serving(json(envelope(
                new ArrayList<>(), "errors", Collections.singletonList(detail))));

        BulkCheckResult result =
                client(exchange).nonprofits().checkBulk(eins("996589560", "411787098"));

        assertEquals(Arrays.asList("996589560", "411787098"), result.getNotFoundEins());
    }

    @Test
    @DisplayName("reads organizations from a wrapped data object as well as a bare array")
    void readsWrappedOrganizations() {
        StubExchange exchange = StubExchange.serving(json(envelope(
                Collections.singletonMap(
                        "organizations", Collections.singletonList(nonprofit())))));

        BulkCheckResult result = client(exchange).nonprofits().checkBulk(eins("411787097"));

        assertEquals(1, result.getOrganizations().size());
    }

    @Test
    @DisplayName("does not mutate the caller's list")
    void doesNotMutateCallerList() {
        StubExchange exchange = StubExchange.serving(emptyBulk());
        List<String> supplied = eins("41-1787097");

        client(exchange).nonprofits().checkBulk(supplied);

        assertEquals(Collections.singletonList("41-1787097"), supplied);
    }
}
