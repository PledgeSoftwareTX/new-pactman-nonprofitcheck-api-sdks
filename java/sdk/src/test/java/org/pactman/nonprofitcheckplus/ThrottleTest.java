package org.pactman.nonprofitcheckplus;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.pactman.nonprofitcheckplus.support.Fixtures.TEST_API_KEY;
import static org.pactman.nonprofitcheckplus.support.Fixtures.envelope;
import static org.pactman.nonprofitcheckplus.support.Fixtures.json;
import static org.pactman.nonprofitcheckplus.support.Fixtures.nonprofit;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.pactman.nonprofitcheckplus.config.PactmanClientOptions;
import org.pactman.nonprofitcheckplus.support.RecordingHooks;
import org.pactman.nonprofitcheckplus.support.StubExchange;

class ThrottleTest {

    @Test
    @DisplayName("spaces requests when a rate ceiling is configured")
    void spacesRequests() {
        StubExchange exchange = StubExchange.serving(json(envelope(nonprofit())));
        RecordingHooks hooks = new RecordingHooks();

        PactmanClient client = new PactmanClient(
                PactmanClientOptions.builder()
                        .apiKey(TEST_API_KEY)
                        .baseUrl("http://mock.test")
                        .httpExchange(exchange)
                        .maxRequestsPerSecond(4)
                        .build(),
                hooks);

        for (int i = 0; i < 3; i++) {
            client.nonprofits().check("411787097");
        }

        assertEquals(3, exchange.callCount());

        // The first request goes immediately. The recorded clock does not
        // advance while it pretends to wait, so each later request is asked to
        // wait for the whole schedule accumulated so far: 250ms, then 500ms.
        // Against a real clock these would both be about 250ms apart.
        assertEquals(2, hooks.delays().size());
        assertTrue(
                hooks.delays().get(0) > 200 && hooks.delays().get(0) <= 250,
                "unexpected first spacing: " + hooks.delays().get(0));
        assertTrue(
                hooks.delays().get(1) > 450 && hooks.delays().get(1) <= 500,
                "unexpected second spacing: " + hooks.delays().get(1));
    }

    @Test
    @DisplayName("does not throttle when no ceiling is configured")
    void doesNotThrottleByDefault() {
        StubExchange exchange = StubExchange.serving(json(envelope(nonprofit())));
        RecordingHooks hooks = new RecordingHooks();

        PactmanClient client = new PactmanClient(
                PactmanClientOptions.builder()
                        .apiKey(TEST_API_KEY)
                        .baseUrl("http://mock.test")
                        .httpExchange(exchange)
                        .build(),
                hooks);

        for (int i = 0; i < 3; i++) {
            client.nonprofits().check("411787097");
        }

        assertEquals(0, hooks.delays().size());
    }
}
