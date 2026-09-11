package org.pactman.nonprofitcheckplus;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.pactman.nonprofitcheckplus.support.Fixtures.TEST_API_KEY;
import static org.pactman.nonprofitcheckplus.support.Fixtures.envelope;
import static org.pactman.nonprofitcheckplus.support.Fixtures.json;
import static org.pactman.nonprofitcheckplus.support.Fixtures.nonprofit;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import org.pactman.nonprofitcheckplus.config.PactmanClientOptions;
import org.pactman.nonprofitcheckplus.config.RetryOptions;
import org.pactman.nonprofitcheckplus.exceptions.PactmanConfigurationException;
import org.pactman.nonprofitcheckplus.support.StubExchange;

class ConfigTest {

    private static PactmanClientOptions.Builder options() {
        return PactmanClientOptions.builder().apiKey(TEST_API_KEY);
    }

    @Test
    @DisplayName("defaults to production with the documented timeout and retry policy")
    void appliesDefaults() {
        PactmanClient client = new PactmanClient(options().build());

        assertEquals("https://entities.pactman.org", client.baseUrl());
        assertEquals(PactmanEnvironment.PRODUCTION, client.environment());
        assertEquals(PactmanClientOptions.DEFAULT_TIMEOUT_MS, client.timeoutMs());
        assertEquals(2, client.retry().maxRetries());
    }

    @Test
    @DisplayName("declares no environment when an explicit base URL is given")
    void explicitBaseUrlClearsEnvironment() {
        PactmanClient client = new PactmanClient(options().baseUrl("https://mock.test").build());

        assertEquals("https://mock.test", client.baseUrl());
        assertNull(client.environment());
    }

    @Test
    @DisplayName("strips trailing slashes from a base URL but keeps a path prefix")
    void normalizesBaseUrl() {
        assertEquals(
                "https://gateway.test/pactman",
                new PactmanClient(options().baseUrl("https://gateway.test/pactman//").build())
                        .baseUrl());
    }

    @ParameterizedTest
    @ValueSource(strings = {"", "   "})
    @DisplayName("rejects a blank API key")
    void rejectsBlankApiKey(String apiKey) {
        assertThrows(
                PactmanConfigurationException.class,
                () -> new PactmanClient(PactmanClientOptions.builder().apiKey(apiKey).build()));
    }

    @Test
    @DisplayName("rejects a missing API key with a message that says where to get one")
    void rejectsMissingApiKey() {
        PactmanConfigurationException failure = assertThrows(
                PactmanConfigurationException.class,
                () -> new PactmanClient(PactmanClientOptions.builder().build()));

        assertTrue(failure.getMessage().contains("PACTMAN_API_KEY"));
    }

    @ParameterizedTest
    @ValueSource(strings = {"not a url", "ftp://entities.pactman.org", "/relative/only"})
    @DisplayName("rejects a base URL that is not an absolute http(s) URL")
    void rejectsMalformedBaseUrl(String baseUrl) {
        assertThrows(
                PactmanConfigurationException.class,
                () -> new PactmanClient(options().baseUrl(baseUrl).build()));
    }

    @Test
    @DisplayName("rejects a timeout of zero or less, with no way to disable it")
    void rejectsNonPositiveTimeout() {
        assertThrows(
                PactmanConfigurationException.class,
                () -> new PactmanClient(options().timeoutMs(0).build()));
        assertThrows(
                PactmanConfigurationException.class,
                () -> new PactmanClient(options().timeoutMs(-1).build()));
    }

    @Test
    @DisplayName("rejects a rate ceiling that is not a positive finite number")
    void rejectsNonPositiveRateCeiling() {
        assertThrows(
                PactmanConfigurationException.class,
                () -> new PactmanClient(options().maxRequestsPerSecond(0).build()));
        assertThrows(
                PactmanConfigurationException.class,
                () -> new PactmanClient(options().maxRequestsPerSecond(Double.NaN).build()));
    }

    @Test
    @DisplayName("rejects a nonsensical retry policy where it is built")
    void rejectsNonsensicalRetryPolicy() {
        assertThrows(
                PactmanConfigurationException.class,
                () -> RetryOptions.builder().maxRetries(-1).build());
        assertThrows(
                PactmanConfigurationException.class,
                () -> RetryOptions.builder().backoffFactor(0.5d).build());
    }

    @Test
    @DisplayName("never retries a rejected key, whatever the policy says")
    void neverRetriesAuthFailures() {
        RetryOptions permissive = RetryOptions.builder()
                .retryableStatuses(new java.util.LinkedHashSet<>(
                        java.util.Arrays.asList(400, 401, 403, 404, 429, 500)))
                .build();

        assertFalse(permissive.isRetryableStatus(401));
        assertFalse(permissive.isRetryableStatus(403));
        assertFalse(permissive.isRetryableStatus(400));
        assertFalse(permissive.isRetryableStatus(404));
        assertTrue(permissive.isRetryableStatus(429));
        assertTrue(permissive.isRetryableStatus(500));
    }

    @Test
    @DisplayName("sends default headers, and never lets one replace the credential")
    void defaultHeadersCannotReplaceCredential() {
        StubExchange exchange = StubExchange.serving(json(envelope(nonprofit())));
        PactmanClient client = new PactmanClient(options()
                .baseUrl("http://mock.test")
                .httpExchange(exchange)
                .defaultHeader("X-Tenant", "acme")
                .defaultHeader("Authorization", "Bearer not-the-real-key")
                .build());

        client.nonprofits().check("411787097");

        assertEquals("acme", exchange.request(0).header("x-tenant"));
        assertEquals("Bearer " + TEST_API_KEY, exchange.request(0).header("authorization"));
    }

    @Test
    @DisplayName("keeps the API key out of every diagnostic view")
    void redactsApiKey() {
        PactmanClient client = new PactmanClient(options().build());

        assertFalse(client.toString().contains(TEST_API_KEY));
        assertFalse(client.toMap().toString().contains(TEST_API_KEY));
        assertEquals("[redacted]", client.toMap().get("apiKey"));
    }

    @Test
    @DisplayName("trims a key padded by a careless environment variable")
    void trimsApiKey() {
        StubExchange exchange = StubExchange.serving(json(envelope(nonprofit())));
        PactmanClient client = new PactmanClient(PactmanClientOptions.builder()
                .apiKey("  " + TEST_API_KEY + "\n")
                .baseUrl("http://mock.test")
                .httpExchange(exchange)
                .build());

        client.nonprofits().check("411787097");

        assertEquals("Bearer " + TEST_API_KEY, exchange.request(0).header("authorization"));
    }
}
