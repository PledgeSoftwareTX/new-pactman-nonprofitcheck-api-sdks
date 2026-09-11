package org.pactman.nonprofitcheckplus;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertInstanceOf;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.pactman.nonprofitcheckplus.support.Fixtures.TEST_API_KEY;
import static org.pactman.nonprofitcheckplus.support.Fixtures.client;
import static org.pactman.nonprofitcheckplus.support.Fixtures.envelope;
import static org.pactman.nonprofitcheckplus.support.Fixtures.json;
import static org.pactman.nonprofitcheckplus.support.Fixtures.nonprofit;

import java.util.concurrent.CancellationException;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutionException;
import java.util.concurrent.TimeUnit;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.Timeout;
import org.pactman.nonprofitcheckplus.config.PactmanClientOptions;
import org.pactman.nonprofitcheckplus.config.RequestOptions;
import org.pactman.nonprofitcheckplus.config.RetryOptions;
import org.pactman.nonprofitcheckplus.exceptions.PactmanNetworkException;
import org.pactman.nonprofitcheckplus.exceptions.PactmanTimeoutException;
import org.pactman.nonprofitcheckplus.models.SingleCheckResult;
import org.pactman.nonprofitcheckplus.support.RecordingHooks;
import org.pactman.nonprofitcheckplus.support.StubExchange;
import org.pactman.nonprofitcheckplus.support.StubResponse;

class TimeoutTest {

    private static PactmanClient clientWith(StubExchange exchange, long timeoutMs, int maxRetries) {
        return new PactmanClient(
                PactmanClientOptions.builder()
                        .apiKey(TEST_API_KEY)
                        .baseUrl("http://mock.test")
                        .httpExchange(exchange)
                        .timeoutMs(timeoutMs)
                        .retry(RetryOptions.builder().maxRetries(maxRetries).build())
                        .build(),
                new RecordingHooks());
    }

    @Test
    @Timeout(10)
    @DisplayName("gives up on a response that never arrives, and says what it waited")
    void timesOutWhenNoResponseArrives() {
        StubExchange exchange = new StubExchange(StubExchange.NEVER_RESPONDS);

        PactmanTimeoutException failure = assertThrows(
                PactmanTimeoutException.class,
                () -> clientWith(exchange, 50, 0).nonprofits().check("411787097"));

        assertEquals(50L, failure.timeoutMs());
        assertEquals(1, failure.attempts());
        assertTrue(failure.getMessage().contains("50ms"));
    }

    @Test
    @Timeout(10)
    @DisplayName("retries a timeout, and succeeds when the next attempt answers")
    void retriesTimeout() {
        StubExchange exchange = new StubExchange(
                StubExchange.NEVER_RESPONDS, StubResponse.json(json(envelope(nonprofit()))));

        SingleCheckResult result = clientWith(exchange, 50, 2).nonprofits().check("411787097");

        assertEquals("EXAMPLE NONPROFIT", result.getNonprofit().getOrganizationName());
        assertEquals(2, exchange.callCount());
    }

    @Test
    @Timeout(10)
    @DisplayName("a per-request timeout overrides the client's for that call only")
    void perRequestTimeoutOverridesClient() {
        StubExchange exchange = new StubExchange(StubExchange.NEVER_RESPONDS);
        PactmanClient client = clientWith(exchange, 30_000, 0);

        PactmanTimeoutException failure = assertThrows(
                PactmanTimeoutException.class,
                () -> client.nonprofits().check("411787097", new RequestOptions().timeoutMs(40)));

        assertEquals(40L, failure.timeoutMs());
        assertEquals(30_000L, client.timeoutMs(), "the client's own timeout is unchanged");
    }

    @Test
    @Timeout(10)
    @DisplayName("cancelling the future stops the call rather than leaving it running")
    void cancellingFutureStopsTheCall() throws Exception {
        CountDownLatch started = new CountDownLatch(1);

        try (PactmanClient client = new PactmanClient(
                PactmanClientOptions.builder()
                        .apiKey(TEST_API_KEY)
                        .baseUrl("http://mock.test")
                        .httpExchange(request -> {
                            started.countDown();
                            return new CompletableFuture<>();
                        })
                        .timeoutMs(30_000)
                        .build())) {

            CompletableFuture<SingleCheckResult> pending =
                    client.nonprofits().checkAsync("411787097");

            assertTrue(started.await(5, TimeUnit.SECONDS), "the call should have been sent");
            assertTrue(pending.cancel(true));
            assertThrows(CancellationException.class, () -> pending.get(5, TimeUnit.SECONDS));
        }
    }

    @Test
    @Timeout(10)
    @DisplayName("an interrupted thread reports cancellation, not a timeout")
    void interruptionReportsCancellation() throws Exception {
        StubExchange exchange = new StubExchange(StubExchange.NEVER_RESPONDS);
        PactmanClient client = clientWith(exchange, 30_000, 0);

        CompletableFuture<Throwable> caught = new CompletableFuture<>();
        Thread worker = new Thread(() -> {
            try {
                client.nonprofits().check("411787097");
                caught.complete(null);
            } catch (RuntimeException failure) {
                caught.complete(failure);
            }
        });

        worker.start();
        Thread.sleep(100);
        worker.interrupt();

        Throwable failure = caught.get(5, TimeUnit.SECONDS);

        assertInstanceOf(PactmanNetworkException.class, failure);
        assertTrue(failure.getMessage().contains("cancelled"));
    }

    @Test
    @Timeout(10)
    @DisplayName("an async call surfaces the same exception a blocking one would")
    void asyncSurfacesTheSameException() throws Exception {
        StubExchange exchange = new StubExchange(StubResponse.empty(401));

        try (PactmanClient client = new PactmanClient(
                PactmanClientOptions.builder()
                        .apiKey(TEST_API_KEY)
                        .baseUrl("http://mock.test")
                        .httpExchange(exchange)
                        .build())) {

            ExecutionException wrapped = assertThrows(
                    ExecutionException.class,
                    () -> client.nonprofits().checkAsync("411787097").get(5, TimeUnit.SECONDS));

            assertInstanceOf(
                    org.pactman.nonprofitcheckplus.exceptions.PactmanAuthenticationException.class,
                    wrapped.getCause());
        }
    }

    @Test
    @Timeout(10)
    @DisplayName("async results carry the same data as blocking ones")
    void asyncReturnsTheSameResult() throws Exception {
        StubExchange exchange = StubExchange.serving(json(envelope(nonprofit())));

        try (PactmanClient client = new PactmanClient(
                PactmanClientOptions.builder()
                        .apiKey(TEST_API_KEY)
                        .baseUrl("http://mock.test")
                        .httpExchange(exchange)
                        .build())) {

            SingleCheckResult result =
                    client.nonprofits().checkAsync("411787097").get(5, TimeUnit.SECONDS);

            assertEquals("EXAMPLE NONPROFIT", result.getNonprofit().getOrganizationName());
        }
    }
}
