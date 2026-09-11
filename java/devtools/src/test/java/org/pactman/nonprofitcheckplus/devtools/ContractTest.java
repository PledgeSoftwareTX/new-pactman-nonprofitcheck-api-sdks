package org.pactman.nonprofitcheckplus.devtools;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.util.Arrays;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.Set;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.CsvSource;
import org.pactman.nonprofitcheckplus.internal.Json;

/**
 * The response-signature engine the smoke and baseline tools share.
 *
 * <p>This is the part of the tooling with real logic in it, and the part whose
 * mistakes are silent: a differ that under-reports passes a green run over a
 * broken API, and one that over-reports gets switched off. The rules that are
 * easy to get subtly wrong are the ones about absence — a field missing because
 * it was removed, versus one missing because the object it lives in arrived
 * null. Getting that backwards either fails every green run or passes every
 * broken one, and neither is visible without a live deployment to try it
 * against, so it is pinned here.
 */
class ContractTest {

    private static Map<String, String> signature(String json) {
        return Contract.signatureOf(Json.parse(json));
    }

    private static Map<String, String> map(String... pairs) {
        Map<String, String> signature = new LinkedHashMap<>();

        for (int i = 0; i + 1 < pairs.length; i += 2) {
            signature.put(pairs[i], pairs[i + 1]);
        }

        return signature;
    }

    @ParameterizedTest
    @CsvSource({
        "411787097, digits:9",
        "01085-2643, digits:5-4",
        "00, digits:2",
        "'3/25/2026 3:28:54 PM', date",
        "'2026-08-24T09:47:53Z', date:iso",
        "https://pactman.org/profile, url",
        "'', empty",
        "'   ', empty",
        "EXAMPLE NONPROFIT, text",
    })
    @DisplayName("classifies a string by its form, never by its value")
    void classifiesStringsByForm(String value, String expected) {
        assertEquals(expected, Contract.formatOf(value));
    }

    @Test
    @DisplayName("both OFAC wordings share one token")
    void bothOfacWordingsShareOneToken() {
        assertEquals("ofac-sentence", Contract.formatOf(Fixtures.OFAC_NO_MATCH));
        assertEquals("ofac-sentence", Contract.formatOf(Fixtures.OFAC_POSSIBLE_MATCH));
    }

    @Test
    @DisplayName("a genuine wording change falls back to text")
    void wordingChangeFallsBackToText() {
        assertEquals(
                "text",
                Contract.formatOf("This organization is not on any watchlist we checked."));
    }

    @Test
    @DisplayName("flattens a response into paths and tokens")
    void flattensAResponse() {
        Map<String, String> signature = signature(
                "{\"code\":200,\"data\":{\"ein\":\"411787097\",\"pub78_verified\":true,"
                        + "\"revocation_code\":null,\"organization_types\":"
                        + "[{\"deductibility_limitation\":\"50%\"}]},\"errors\":null}");

        assertEquals("number", signature.get("code"));
        assertEquals("object", signature.get("data"));
        assertEquals("digits:9", signature.get("data.ein"));
        assertEquals("boolean", signature.get("data.pub78_verified"));
        assertEquals("null", signature.get("data.revocation_code"));
        assertEquals("array", signature.get("data.organization_types"));
        assertEquals("object", signature.get("data.organization_types[]"));
        assertEquals(
                "text", signature.get("data.organization_types[].deductibility_limitation"));
        assertEquals("null", signature.get("errors"));
    }

    @Test
    @DisplayName("every element of an array folds into one path")
    void arrayElementsFoldIntoOnePath() {
        Map<String, String> signature = signature(
                "{\"data\":[{\"ein\":\"411787097\"},{\"ein\":\"996589560\"}]}");

        assertEquals("array", signature.get("data"));
        assertEquals("object", signature.get("data[]"));
        assertEquals("digits:9", signature.get("data[].ein"));
        assertEquals(3, signature.size(), "two organizations describe one record shape");
    }

    @Test
    @DisplayName("a path with two forms records both, sorted")
    void mixedFormsAreRecordedTogether() {
        Map<String, String> signature = signature(
                "{\"data\":[{\"most_recent_bmf\":\"3/25/2026 3:28:54 PM\"},"
                        + "{\"most_recent_bmf\":null}]}");

        assertEquals("date|null", signature.get("data[].most_recent_bmf"));
    }

    @Test
    @DisplayName("records no value from the response")
    void recordsNoValues() {
        Map<String, String> signature = signature(
                "{\"data\":{\"ein\":\"411787097\",\"organization_name\":\"EXAMPLE NONPROFIT\"}}");

        for (String token : signature.values()) {
            assertFalse(token.contains("411787097"), "a signature must carry no value");
            assertFalse(token.contains("EXAMPLE"), "a signature must carry no value");
        }
    }

    @Test
    @DisplayName("schemaDiff reports fields that appeared and disappeared, and nothing else")
    void schemaDiffReportsPresenceOnly() {
        Difference diff = Contract.schemaDiff(
                map("kept", "text", "gone", "text", "moved", "text"),
                map("kept", "text", "moved", "number", "fresh", "text"));

        assertEquals(2, diff.total());
        assertEquals(Change.Kind.REMOVED, diff.changes().get(0).kind());
        assertEquals("gone", diff.changes().get(0).path());
        assertEquals(Change.Kind.ADDED, diff.changes().get(1).kind());
        assertEquals("fresh", diff.changes().get(1).path());
    }

    @Test
    @DisplayName("typeDiff reports only paths both signatures have")
    void typeDiffReportsSharedPathsOnly() {
        Difference diff = Contract.typeDiff(
                map("kept", "text", "gone", "text", "moved", "digits:9"),
                map("kept", "text", "moved", "text", "fresh", "text"));

        assertEquals(1, diff.total());
        assertEquals("moved", diff.changes().get(0).path());
        assertEquals("digits:9", diff.changes().get(0).from());
        assertEquals("text", diff.changes().get(0).to());
    }

    @Test
    @DisplayName("baselineDiff excuses a value that simply did not arrive this time")
    void baselineDiffExcusesNullability() {
        Difference diff = Contract.baselineDiff(
                map("data.pub78_city", "text", "data.most_recent_bmf", "date"),
                map("data.pub78_city", "null", "data.most_recent_bmf", "date|null"));

        assertTrue(diff.clean(), "neither difference is the API moving");
        assertEquals(2, diff.nullable());
    }

    @Test
    @DisplayName("baselineDiff still reports a move between two forms a value took")
    void baselineDiffReportsRealDrift() {
        Difference diff = Contract.baselineDiff(
                map("data.ein", "digits:9"), map("data.ein", "text"));

        assertEquals(1, diff.total());
        assertEquals("digits:9", diff.changes().get(0).from());
    }

    @Test
    @DisplayName("baselineDiff excuses paths under a parent that arrived null, in both directions")
    void baselineDiffExcusesUnreachablePaths() {
        Map<String, String> populated = map(
                "data.organization_types", "array",
                "data.organization_types[]", "object",
                "data.organization_types[].deductibility_limitation", "text");
        Map<String, String> empty = map("data.organization_types", "null");

        Difference forwards = Contract.baselineDiff(populated, empty);
        Difference backwards = Contract.baselineDiff(empty, populated);

        assertTrue(forwards.clean());
        assertEquals(2, forwards.unreachable());
        assertTrue(backwards.clean());
        assertEquals(2, backwards.unreachable());
    }

    @Test
    @DisplayName("an empty array leaves its members unreachable too")
    void emptyArrayLeavesMembersUnreachable() {
        Difference diff = Contract.baselineDiff(
                map("errors", "array", "errors[]", "object", "errors[].reason", "text"),
                map("errors", "array"));

        assertTrue(diff.clean());
        assertEquals(2, diff.unreachable());
    }

    @Test
    @DisplayName("permits treats `string` as a wildcard over every string form")
    void stringIsAWildcard() {
        assertTrue(Contract.permits("null|string", "text"));
        assertTrue(Contract.permits("null|string", "date"));
        assertTrue(Contract.permits("null|string", "digits:9"));
        assertTrue(Contract.permits("null|string", "url"));
        assertTrue(Contract.permits("null|string", "null"));

        // Where the contract names a form, a different string form fails.
        assertTrue(Contract.permits("digits:9|null", "digits:9"));
        assertFalse(Contract.permits("digits:9|null", "text"));
        assertFalse(Contract.permits("digits:9|null", "digits:5-4"));

        assertFalse(Contract.permits("null|string", "number"));
        assertFalse(Contract.permits("boolean|null", "text"));
    }

    @Test
    @DisplayName("composeExpected describes one record shape for both endpoints")
    void composeExpectedSharesOneRecordShape() {
        Map<String, Object> contract = ContractResources.contract();
        Map<String, String> single = Contract.composeExpected(contract, Contract.Kind.SINGLE);
        Map<String, String> bulk = Contract.composeExpected(contract, Contract.Kind.BULK);

        assertEquals("null|object", single.get("data"));
        assertEquals("array|null", bulk.get("data"));
        assertEquals("object", bulk.get("data[]"));

        // The same field, described identically under each prefix.
        assertEquals(single.get("data.ein"), bulk.get("data[].ein"));
        assertEquals(
                single.get("data.organization_types[].deductibility_limitation"),
                bulk.get("data[].organization_types[].deductibility_limitation"));
        assertEquals("null|object", single.get("data.organization_types[]"));
    }

    @Test
    @DisplayName("coverageDiff passes a response whose absent paths sit under a null parent")
    void coverageDiffExcusesUnreachablePaths() {
        Map<String, String> expected = map(
                "code", "number",
                "data", "null|object",
                "data.ein", "digits:9",
                "data.organization_types", "array|null",
                "data.organization_types[]", "null|object",
                "data.organization_types[].organization_type", "null|string",
                "errors", "array|null|string",
                "errors[]", "object",
                "errors[].reason", "string");

        Map<String, String> observed = map(
                "code", "number",
                "data", "object",
                "data.ein", "digits:9",
                "data.organization_types", "null",
                "errors", "null");

        Difference diff = Contract.coverageDiff(expected, observed, null);

        assertTrue(diff.clean());
        // errors[], errors[].reason, organization_types[] and its one field.
        assertEquals(4, diff.unreachable());
    }

    @Test
    @DisplayName("coverageDiff reports a vanished container once, at its shallowest path")
    void coverageDiffReportsAContainerOnce() {
        Map<String, String> expected = map(
                "code", "number",
                "data", "null|object",
                "data.ein", "digits:9",
                "data.organization_name", "null|string");

        Difference diff = Contract.coverageDiff(expected, map("code", "number"), null);

        assertEquals(1, diff.total());
        assertEquals("data", diff.changes().get(0).path());
    }

    @Test
    @DisplayName("coverageDiff reports a field the API invented")
    void coverageDiffReportsUnpredictedFields() {
        Difference diff = Contract.coverageDiff(
                map("code", "number"), map("code", "number", "data.brand_new", "text"), null);

        assertEquals(1, diff.total());
        assertEquals(Change.Kind.ADDED, diff.changes().get(0).kind());
        assertEquals("data.brand_new", diff.changes().get(0).path());
    }

    @Test
    @DisplayName("coverageDiff excuses an absent field nothing promises is present")
    void coverageDiffExcusesOptionalAbsence() {
        Map<String, String> expected =
                map("code", "number", "data", "object", "data.address_line2", "null|string");
        Map<String, String> observed = map("code", "number", "data", "object");

        Difference required = Contract.coverageDiff(expected, observed, null);
        Difference optional = Contract.coverageDiff(
                expected, observed, Set.of("code", "data"));

        assertEquals(1, required.total(), "with no policy, every predicted path is required");
        assertTrue(optional.clean());
        assertEquals(1, optional.optionalAbsent());
    }

    @Test
    @DisplayName("this SDK promises no field is always present, so nothing is required of a record")
    void nothingIsRequiredOfARecord() {
        Map<String, Object> contract = ContractResources.contract();
        Set<String> required = Contract.requiredPathsOf(contract, Contract.Kind.SINGLE);

        // Only the structural paths the envelope always has.
        assertEquals(
                Set.of("data", "errors[]", "errors[].eins[]", "data.organization_types[]"),
                required);
    }

    @Test
    @DisplayName("removals are reported before changes, and changes before additions")
    void changesAreOrderedBySeverity() {
        Difference diff = Contract.baselineDiff(
                map("gone", "text", "moved", "digits:9"),
                map("moved", "text", "fresh", "text"));

        assertEquals(
                Arrays.asList(Change.Kind.REMOVED, Change.Kind.CHANGED, Change.Kind.ADDED),
                Arrays.asList(
                        diff.changes().get(0).kind(),
                        diff.changes().get(1).kind(),
                        diff.changes().get(2).kind()));
    }

    @Test
    @DisplayName("summarize names only the counts that are not zero")
    void summarizeNamesNonZeroCounts() {
        Difference diff = Contract.schemaDiff(map("gone", "text"), map("fresh", "text"));

        assertEquals("1 removed, 1 added", Contract.summarize(diff.changes()));
        assertEquals("no differences", Contract.summarize(java.util.Collections.emptyList()));
    }

    @Test
    @DisplayName("the fixture API answers with a shape the contract permits")
    void theFixtureApiMatchesTheContract() throws Exception {
        // The stand-in API is what every example and the smoke runner exercise.
        // If it drifted from the contract, all of them would be rehearsing
        // against a shape the real service does not produce.
        Map<String, Object> contract = ContractResources.contract();
        Map<String, String> expected =
                Contract.composeExpected(contract, Contract.Kind.SINGLE);

        try (FixtureApi api = FixtureApi.start("test-key")) {
            java.net.http.HttpClient client = java.net.http.HttpClient.newHttpClient();
            java.net.http.HttpRequest request = java.net.http.HttpRequest.newBuilder(
                            java.net.URI.create(api.baseUrl()
                                    + "/api/entities/nonprofitcheck/v1/us/ein/"
                                    + FixtureEins.PUBLIC_CHARITY))
                    .header("Authorization", "Bearer test-key")
                    .build();

            String body = client.send(
                            request, java.net.http.HttpResponse.BodyHandlers.ofString())
                    .body();

            Map<String, String> observed = Contract.signatureOf(Json.parse(body));
            Difference types = Contract.contractDiff(expected, observed);
            Difference coverage = Contract.coverageDiff(
                    expected, observed, Contract.requiredPathsOf(contract, Contract.Kind.SINGLE));

            assertTrue(
                    types.clean(),
                    "the fixture API carries a value the contract forbids: "
                            + Contract.formatChanges(types.changes(), ""));
            assertTrue(
                    coverage.clean(),
                    "the fixture API and the contract disagree about fields: "
                            + Contract.formatChanges(coverage.changes(), ""));
        }
    }
}
