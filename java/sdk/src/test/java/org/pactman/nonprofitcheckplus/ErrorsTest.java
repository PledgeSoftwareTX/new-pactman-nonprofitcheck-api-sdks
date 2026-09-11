package org.pactman.nonprofitcheckplus;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertInstanceOf;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.pactman.nonprofitcheckplus.support.Fixtures.TEST_API_KEY;
import static org.pactman.nonprofitcheckplus.support.Fixtures.client;
import static org.pactman.nonprofitcheckplus.support.Fixtures.json;

import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.Map;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.CsvSource;
import org.pactman.nonprofitcheckplus.exceptions.ErrorCategory;
import org.pactman.nonprofitcheckplus.exceptions.ErrorOrigin;
import org.pactman.nonprofitcheckplus.exceptions.PactmanApiException;
import org.pactman.nonprofitcheckplus.exceptions.PactmanAuthenticationException;
import org.pactman.nonprofitcheckplus.exceptions.PactmanAuthorizationException;
import org.pactman.nonprofitcheckplus.exceptions.PactmanBadRequestException;
import org.pactman.nonprofitcheckplus.exceptions.PactmanException;
import org.pactman.nonprofitcheckplus.exceptions.PactmanNetworkException;
import org.pactman.nonprofitcheckplus.exceptions.PactmanNotFoundException;
import org.pactman.nonprofitcheckplus.exceptions.PactmanRateLimitException;
import org.pactman.nonprofitcheckplus.exceptions.PactmanServerException;
import org.pactman.nonprofitcheckplus.exceptions.PactmanValidationException;
import org.pactman.nonprofitcheckplus.support.StubExchange;
import org.pactman.nonprofitcheckplus.support.StubResponse;

class ErrorsTest {

    private static String errorBody(int code, String reason) {
        Map<String, Object> detail = new LinkedHashMap<>();
        detail.put("resource", "nonprofitcheck");
        detail.put("reason", reason);
        detail.put("code", (long) code);

        Map<String, Object> envelope = new LinkedHashMap<>();
        envelope.put("code", (long) code);
        envelope.put("message", "Request failed");
        envelope.put("errors", Collections.singletonList(detail));
        envelope.put("data", null);

        return json(envelope);
    }

    @ParameterizedTest
    @CsvSource({
        "400, org.pactman.nonprofitcheckplus.exceptions.PactmanBadRequestException",
        "401, org.pactman.nonprofitcheckplus.exceptions.PactmanAuthenticationException",
        "403, org.pactman.nonprofitcheckplus.exceptions.PactmanAuthorizationException",
        "404, org.pactman.nonprofitcheckplus.exceptions.PactmanNotFoundException",
        "429, org.pactman.nonprofitcheckplus.exceptions.PactmanRateLimitException",
        "500, org.pactman.nonprofitcheckplus.exceptions.PactmanServerException",
        "503, org.pactman.nonprofitcheckplus.exceptions.PactmanServerException",
    })
    @DisplayName("maps each status to its own exception type")
    void mapsStatusToExceptionType(int status, String expected) throws ClassNotFoundException {
        StubExchange exchange = new StubExchange(
                StubResponse.of(status, errorBody(status, "something went wrong")));

        PactmanException failure = assertThrows(
                PactmanException.class,
                () -> client(exchange, new org.pactman.nonprofitcheckplus.support.RecordingHooks())
                        .nonprofits()
                        .check("411787097"));

        assertInstanceOf(Class.forName(expected), failure);
    }

    @Test
    @DisplayName("prefers the API's own reason over a generic message")
    void prefersApiReason() {
        StubExchange exchange =
                new StubExchange(StubResponse.of(400, errorBody(400, "EIN must be nine digits")));

        PactmanBadRequestException failure = assertThrows(
                PactmanBadRequestException.class,
                () -> client(exchange).nonprofits().check("411787097"));

        assertEquals("EIN must be nine digits", failure.getMessage());
        assertEquals(400, failure.status());
        assertEquals(Integer.valueOf(400), failure.apiCode());
        assertEquals(1, failure.apiErrors().size());
        assertEquals("nonprofitcheck", failure.apiErrors().get(0).getResource());
    }

    @Test
    @DisplayName("falls back to a message that names the status when the body has none")
    void fallsBackToStatusMessage() {
        StubExchange exchange = new StubExchange(StubResponse.empty(502));

        PactmanServerException failure = assertThrows(
                PactmanServerException.class,
                () -> client(exchange, new org.pactman.nonprofitcheckplus.support.RecordingHooks())
                        .nonprofits()
                        .check("411787097"));

        assertTrue(failure.getMessage().contains("502"));
        assertNull(failure.apiMessage());
        assertEquals(ErrorCategory.SERVER, failure.category());
    }

    @Test
    @DisplayName("keeps an unparseable body as evidence rather than discarding it")
    void keepsUnparseableBody() {
        StubExchange exchange = new StubExchange(
                StubResponse.of(500, "<html><body>Gateway exploded</body></html>"));

        PactmanServerException failure = assertThrows(
                PactmanServerException.class,
                () -> client(exchange, new org.pactman.nonprofitcheckplus.support.RecordingHooks())
                        .nonprofits()
                        .check("411787097"));

        assertTrue(failure.getMessage().contains("Gateway exploded"));
        assertInstanceOf(String.class, failure.raw());
    }

    @Test
    @DisplayName("carries the correlation id and Retry-After through to the exception")
    void carriesResponseMetadata() {
        StubExchange exchange = new StubExchange(
                StubResponse.of(429, errorBody(429, "Rate limit exceeded"))
                        .header("retry-after", "3")
                        .header("x-request-id", "req-42"));

        PactmanRateLimitException failure = assertThrows(
                PactmanRateLimitException.class,
                () -> client(exchange, new org.pactman.nonprofitcheckplus.support.RecordingHooks())
                        .nonprofits()
                        .check("411787097"));

        assertEquals("req-42", failure.requestId());
        assertEquals(Double.valueOf(3), failure.retryAfterSeconds());
        assertEquals(ErrorCategory.RATE_LIMIT, failure.category());
        assertEquals(ErrorOrigin.API, failure.origin());
    }

    @Test
    @DisplayName("reports a transport failure as a network error, not a timeout")
    void reportsTransportFailureAsNetwork() {
        StubExchange exchange = new StubExchange(StubExchange.networkFailure());

        PactmanNetworkException failure = assertThrows(
                PactmanNetworkException.class,
                () -> client(exchange, new org.pactman.nonprofitcheckplus.support.RecordingHooks())
                        .nonprofits()
                        .check("411787097"));

        assertEquals(ErrorCategory.NETWORK, failure.category());
        assertEquals(ErrorOrigin.LOCAL, failure.origin());
        assertTrue(failure.getMessage().contains("connection reset"));
    }

    @Test
    @DisplayName("separates a local validation failure from an API-side rejection")
    void separatesLocalValidationFromApiRejection() {
        StubExchange exchange = new StubExchange(StubResponse.of(400, errorBody(400, "rejected")));

        PactmanValidationException local = assertThrows(
                PactmanValidationException.class,
                () -> client(exchange).nonprofits().check("nope"));
        assertEquals(ErrorOrigin.LOCAL, local.origin());
        assertEquals(0, exchange.callCount());

        PactmanApiException remote = assertThrows(
                PactmanApiException.class,
                () -> client(exchange).nonprofits().check("411787097"));
        assertEquals(ErrorOrigin.API, remote.origin());
    }

    @Test
    @DisplayName("never puts the API key in a message, a property, or toMap")
    void neverLeaksApiKey() {
        StubExchange exchange = new StubExchange(StubResponse.of(401, errorBody(401, "bad key")));

        PactmanAuthenticationException failure = assertThrows(
                PactmanAuthenticationException.class,
                () -> client(exchange).nonprofits().check("411787097"));

        assertFalse(failure.getMessage().contains(TEST_API_KEY));
        assertFalse(failure.toMap().toString().contains(TEST_API_KEY));
        assertFalse(String.valueOf(failure.raw()).contains(TEST_API_KEY));
    }

    @Test
    @DisplayName("every exception is a PactmanException, so one catch covers the SDK")
    void everyExceptionSharesABase() {
        for (PactmanException failure : new PactmanException[] {
            new PactmanValidationException("bad input"),
            new PactmanNetworkException("dropped", 1, null),
            PactmanApiException.fromStatus(
                    org.pactman.nonprofitcheckplus.exceptions.ApiErrorInit.builder(404).build()),
        }) {
            assertInstanceOf(PactmanException.class, failure);
            assertTrue(failure.toMap().containsKey("category"));
        }

        assertInstanceOf(
                PactmanNotFoundException.class,
                PactmanApiException.fromStatus(
                        org.pactman.nonprofitcheckplus.exceptions.ApiErrorInit.builder(404).build()));
        assertInstanceOf(
                PactmanAuthorizationException.class,
                PactmanApiException.fromStatus(
                        org.pactman.nonprofitcheckplus.exceptions.ApiErrorInit.builder(403).build()));
    }

    @Test
    @DisplayName("survives Java serialization with its identifying fields intact")
    void survivesJavaSerialization() throws Exception {
        StubExchange exchange = new StubExchange(
                StubResponse.of(429, errorBody(429, "Rate limit exceeded"))
                        .header("retry-after", "3")
                        .header("x-request-id", "req-42"));

        PactmanRateLimitException original = assertThrows(
                PactmanRateLimitException.class,
                () -> client(exchange, new org.pactman.nonprofitcheckplus.support.RecordingHooks())
                        .nonprofits()
                        .check("411787097"));

        PactmanRateLimitException restored = roundTrip(original);

        // Everything a handler branches on comes back.
        assertEquals(original.getMessage(), restored.getMessage());
        assertEquals(ErrorCategory.RATE_LIMIT, restored.category());
        assertEquals(ErrorOrigin.API, restored.origin());
        assertEquals(429, restored.status());
        assertEquals(original.requestId(), restored.requestId());
        assertEquals(original.retryAfterSeconds(), restored.retryAfterSeconds());
        assertEquals(original.attempts(), restored.attempts());

        // The decoded body does not, and says so by being empty rather than by
        // throwing on the first read.
        assertEquals(0, restored.apiErrors().size());
        assertNull(restored.raw());
    }

    @Test
    @DisplayName("a deserialized validation failure reports no issues rather than throwing")
    void deserializedValidationExceptionIsSafeToRead() throws Exception {
        PactmanValidationException restored = roundTrip(
                new PactmanValidationException(
                        "2 of 4 EINs are invalid.",
                        Collections.singletonList(
                                new org.pactman.nonprofitcheckplus.exceptions.ValidationIssue(
                                        "EIN at index 1 is empty.", 1, ""))));

        assertEquals("2 of 4 EINs are invalid.", restored.getMessage());
        assertEquals(0, restored.issues().size());
        assertTrue(restored.toMap().containsKey("issues"));
    }

    @SuppressWarnings("unchecked")
    private static <T> T roundTrip(T value) throws Exception {
        java.io.ByteArrayOutputStream buffer = new java.io.ByteArrayOutputStream();

        try (java.io.ObjectOutputStream out = new java.io.ObjectOutputStream(buffer)) {
            out.writeObject(value);
        }

        try (java.io.ObjectInputStream in = new java.io.ObjectInputStream(
                new java.io.ByteArrayInputStream(buffer.toByteArray()))) {
            return (T) in.readObject();
        }
    }

    @Test
    @DisplayName("surfaces an unmapped 4xx as the general API exception")
    void surfacesUnmappedStatus() {
        StubExchange exchange = new StubExchange(StubResponse.of(418, errorBody(418, "teapot")));

        PactmanApiException failure = assertThrows(
                PactmanApiException.class,
                () -> client(exchange).nonprofits().check("411787097"));

        assertEquals(ErrorCategory.API, failure.category());
        assertEquals(418, failure.status());
    }
}
