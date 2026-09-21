package org.pactman.nonprofitcheckplus;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.pactman.nonprofitcheckplus.support.Fixtures.TEST_API_KEY;
import static org.pactman.nonprofitcheckplus.support.Fixtures.client;
import static org.pactman.nonprofitcheckplus.support.Fixtures.envelope;
import static org.pactman.nonprofitcheckplus.support.Fixtures.json;
import static org.pactman.nonprofitcheckplus.support.Fixtures.nonprofit;

import java.time.Instant;
import java.util.Arrays;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.pactman.nonprofitcheckplus.config.PactmanClientOptions;
import org.pactman.nonprofitcheckplus.config.RequestOptions;
import org.pactman.nonprofitcheckplus.config.RetryOptions;
import org.pactman.nonprofitcheckplus.exceptions.PactmanAuthenticationException;
import org.pactman.nonprofitcheckplus.exceptions.PactmanNetworkException;
import org.pactman.nonprofitcheckplus.exceptions.PactmanServerException;
import org.pactman.nonprofitcheckplus.http.Transport;
import org.pactman.nonprofitcheckplus.support.RecordingHooks;
import org.pactman.nonprofitcheckplus.support.StubExchange;
import org.pactman.nonprofitcheckplus.support.StubResponse;

class RetryTest {

    private static PactmanClient clientWith(
            StubExchange exchange, RecordingHooks hooks, RetryOptions retry) {
        return new PactmanClient(
                PactmanClientOptions.builder()
                        .apiKey(TEST_API_KEY)
                        .baseUrl("http://mock.test")
                        .httpExchange(exchange)
                        .retry(retry)
                        .build(),
                hooks);
    }

    @Test
    @DisplayName("retries a 500 and returns the first success")
    void retriesServerErrorThenSucceeds() {
        StubExchange exchange = new StubExchange(
                StubResponse.empty(500),
                StubResponse.empty(500),
                StubResponse.json(json(envelope(nonprofit()))));
        RecordingHooks hooks = new RecordingHooks();

        assertEquals(
                "EXAMPLE NONPROFIT",
                client(exchange, hooks)
                        .nonprofits()
                        .check("411787097")
                        .getNonprofit()
                        .getOrganizationName());

        assertEquals(3, exchange.callCount());
        assertEquals(2, hooks.delays().size());
    }

    @Test
    @DisplayName("gives up after maxRetries and reports how many attempts were made")
    void givesUpAfterMaxRetries() {
        StubExchange exchange = new StubExchange(StubResponse.empty(503));
        RecordingHooks hooks = new RecordingHooks();

        PactmanServerException failure = assertThrows(
                PactmanServerException.class,
                () -> client(exchange, hooks).nonprofits().check("411787097"));

        assertEquals(3, exchange.callCount());
        assertEquals(3, failure.attempts());
        assertEquals(2, hooks.delays().size());
    }

    @Test
    @DisplayName("backs off exponentially, capped at maxDelayMs")
    void backsOffExponentially() {
        StubExchange exchange = new StubExchange(StubResponse.empty(500));
        RecordingHooks hooks = new RecordingHooks();
        RetryOptions retry = RetryOptions.builder()
                .maxRetries(4)
                .initialDelayMs(100)
                .maxDelayMs(500)
                .backoffFactor(2)
                .jitter(false)
                .build();

        assertThrows(
                PactmanServerException.class,
                () -> clientWith(exchange, hooks, retry).nonprofits().check("411787097"));

        assertEquals(Arrays.asList(100L, 200L, 400L, 500L), hooks.delays());
    }

    @Test
    @DisplayName("spreads jittered delays across the whole computed range")
    void jitterSpreadsDelays() {
        RetryOptions retry = RetryOptions.builder()
                .initialDelayMs(1000)
                .backoffFactor(2)
                .maxDelayMs(60_000)
                .jitter(true)
                .build();

        assertEquals(0L, Transport.computeRetryDelay(1, retry, null, 0.0d));
        assertEquals(500L, Transport.computeRetryDelay(1, retry, null, 0.5d));
        assertEquals(2000L, Transport.computeRetryDelay(2, retry, null, 1.0d));
    }

    @Test
    @DisplayName("never retries a rejected key, however transient it looks")
    void neverRetriesAuthenticationFailure() {
        StubExchange exchange = new StubExchange(StubResponse.empty(401));
        RecordingHooks hooks = new RecordingHooks();

        assertThrows(
                PactmanAuthenticationException.class,
                () -> client(exchange, hooks).nonprofits().check("411787097"));

        assertEquals(1, exchange.callCount());
        assertEquals(0, hooks.delays().size());
    }

    @Test
    @DisplayName("retries a dropped connection")
    void retriesTransportFailure() {
        StubExchange exchange = new StubExchange(
                StubExchange.networkFailure(),
                StubResponse.json(json(envelope(nonprofit()))));
        RecordingHooks hooks = new RecordingHooks();

        assertEquals(
                "411787097",
                client(exchange, hooks).nonprofits().check("411787097").getNonprofit().getEin());
        assertEquals(2, exchange.callCount());
    }

    @Test
    @DisplayName("gives up on a dropped connection once retries are spent")
    void givesUpOnTransportFailure() {
        StubExchange exchange = new StubExchange(StubExchange.networkFailure());
        RecordingHooks hooks = new RecordingHooks();

        PactmanNetworkException failure = assertThrows(
                PactmanNetworkException.class,
                () -> client(exchange, hooks).nonprofits().check("411787097"));

        assertEquals(3, exchange.callCount());
        assertEquals(3, failure.attempts());
    }

    @Test
    @DisplayName("waits the server's Retry-After instead of its own backoff")
    void honorsRetryAfter() {
        StubExchange exchange = new StubExchange(
                StubResponse.empty(429).header("retry-after", "2"),
                StubResponse.json(json(envelope(nonprofit()))));
        RecordingHooks hooks = new RecordingHooks();

        client(exchange, hooks).nonprofits().check("411787097");

        assertEquals(java.util.Collections.singletonList(2000L), hooks.delays());
    }

    @Test
    @DisplayName("reads Retry-After as an HTTP date as well as a delay in seconds")
    void readsRetryAfterAsDate() {
        Instant now = Instant.parse("2026-09-08T12:00:00Z");

        assertEquals(Double.valueOf(30), Transport.readRetryAfter("30", now));
        assertEquals(
                Double.valueOf(60),
                Transport.readRetryAfter("Tue, 8 Sep 2026 12:01:00 GMT", now));
        assertEquals(
                Double.valueOf(0),
                Transport.readRetryAfter("Tue, 8 Sep 2026 11:59:00 GMT", now),
                "a date in the past means retry now, not retry in the past");
        assertEquals(null, Transport.readRetryAfter("soon please", now));
        assertEquals(null, Transport.readRetryAfter("  ", now));
        assertEquals(null, Transport.readRetryAfter("Infinity", now), "no wait can honour it");
        assertEquals(null, Transport.readRetryAfter("1e400", now), "overflows to infinity");
        assertEquals(null, Transport.readRetryAfter("NaN", now));
        assertEquals(null, Transport.readRetryAfter(null, now));
    }

    @Test
    @DisplayName("honors a Retry-After that exceeds maxDelayMs")
    void retryAfterOverridesCap() {
        RetryOptions retry = RetryOptions.builder().maxDelayMs(1000).build();

        assertEquals(30_000L, Transport.computeRetryDelay(1, retry, 30.0d, 1.0d));
    }

    @Test
    @DisplayName("ignores Retry-After when the policy says not to respect it")
    void canIgnoreRetryAfter() {
        RetryOptions retry = RetryOptions.builder()
                .respectRetryAfter(false)
                .initialDelayMs(250)
                .jitter(false)
                .build();

        assertEquals(250L, Transport.computeRetryDelay(1, retry, 30.0d, 1.0d));
    }

    @Test
    @DisplayName("a per-request policy replaces the client's for that call only")
    void perRequestPolicyOverridesClient() {
        StubExchange exchange = new StubExchange(StubResponse.empty(500));
        RecordingHooks hooks = new RecordingHooks();
        PactmanClient client = client(exchange, hooks);

        assertThrows(
                PactmanServerException.class,
                () -> client.nonprofits()
                        .check("411787097", new RequestOptions().retry(RetryOptions.disabled())));
        assertEquals(1, exchange.callCount());

        assertThrows(
                PactmanServerException.class, () -> client.nonprofits().check("411787097"));
        assertEquals(4, exchange.callCount(), "the client's own policy is unchanged");
    }

    @Test
    @DisplayName("retrying is off entirely when the policy is disabled")
    void retryingCanBeDisabled() {
        StubExchange exchange = new StubExchange(StubResponse.empty(500));
        RecordingHooks hooks = new RecordingHooks();

        assertThrows(
                PactmanServerException.class,
                () -> clientWith(exchange, hooks, RetryOptions.disabled())
                        .nonprofits()
                        .check("411787097"));

        assertEquals(1, exchange.callCount());
        assertEquals(0, hooks.delays().size());
    }

    @Test
    @DisplayName("retries a bulk call the same way it retries a single one")
    void retriesBulkCalls() {
        StubExchange exchange = new StubExchange(
                StubResponse.empty(500),
                StubResponse.json(json(envelope(Arrays.asList(nonprofit())))));
        RecordingHooks hooks = new RecordingHooks();

        assertEquals(
                1,
                client(exchange, hooks)
                        .nonprofits()
                        .checkBulk(java.util.Collections.singletonList("411787097"))
                        .getOrganizations()
                        .size());
        assertEquals(2, exchange.callCount());
    }
}
