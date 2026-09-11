package org.pactman.nonprofitcheckplus.examples.cases;

import java.util.concurrent.CompletableFuture;
import java.util.concurrent.TimeUnit;
import org.pactman.nonprofitcheckplus.config.PactmanClientOptions;
import org.pactman.nonprofitcheckplus.config.RequestOptions;
import org.pactman.nonprofitcheckplus.config.RetryOptions;
import org.pactman.nonprofitcheckplus.devtools.FixtureEins;
import org.pactman.nonprofitcheckplus.examples.support.Example;
import org.pactman.nonprofitcheckplus.examples.support.ExampleContext;
import org.pactman.nonprofitcheckplus.examples.support.ExampleFailedException;
import org.pactman.nonprofitcheckplus.examples.support.Output;
import org.pactman.nonprofitcheckplus.exceptions.PactmanTimeoutException;
import org.pactman.nonprofitcheckplus.models.SingleCheckResult;

/**
 * EX-24 — Timeouts and cancellation.
 *
 * <p>The timeout is always finite and there is no way to disable it. Cancellation
 * is separate, and Java already has two ways to express it: interrupt the thread,
 * or cancel the future.
 */
public final class Ex24TimeoutAndCancellation implements Example {

    @Override
    public String id() {
        return "ex-24";
    }

    @Override
    public String title() {
        return "Timeouts, and the two ways to cancel a call";
    }

    @Override
    public void run(String[] args) throws Exception {
        try (ExampleContext context = ExampleContext.withFixtures(
                PactmanClientOptions.builder()
                        .timeoutMs(30_000)
                        .retry(RetryOptions.disabled()))) {

            Output.heading("A per-request timeout");
            Output.field("client timeout", context.client().timeoutMs() + "ms");

            long started = System.currentTimeMillis();

            try {
                context.client()
                        .nonprofits()
                        .check(FixtureEins.CONTROL_SLOW, new RequestOptions().timeoutMs(300));
                throw new ExampleFailedException("Expected the request to time out.");
            } catch (PactmanTimeoutException failure) {
                Output.field("exception", failure.getClass().getSimpleName());
                Output.field("category", failure.category());
                Output.field("timeoutMs", failure.timeoutMs());
                Output.field("attempts", failure.attempts());
                Output.field("wall clock", (System.currentTimeMillis() - started) + "ms");
            }

            Output.field("client timeout after", context.client().timeoutMs() + "ms");

            Output.heading("Cancelling an async call");

            CompletableFuture<SingleCheckResult> pending =
                    context.client().nonprofits().checkAsync(FixtureEins.CONTROL_SLOW);

            // Give it a moment to actually be in flight, then give up on it.
            Thread.sleep(150);
            boolean cancelled = pending.cancel(true);

            Output.field("future.cancel(true)", cancelled);
            Output.field("future.isCancelled()", pending.isCancelled());

            if (!cancelled) {
                throw new ExampleFailedException("The in-flight call should have been cancellable.");
            }

            Output.heading("Cancelling a blocking call");

            Thread worker = new Thread(() -> {
                try {
                    context.client().nonprofits().check(FixtureEins.CONTROL_SLOW);
                } catch (RuntimeException stopped) {
                    Output.field("on the worker thread", stopped.getClass().getSimpleName());
                    Output.field("message", stopped.getMessage());
                }
            });

            worker.start();
            Thread.sleep(150);
            worker.interrupt();
            worker.join(TimeUnit.SECONDS.toMillis(5));
        }

        Output.note("Cancellation is a PactmanNetworkException, not a timeout: nothing expired,\n"
                + "someone asked for the work to stop. Both forms also stop any planned\n"
                + "retries, so a cancelled call does not quietly keep a socket and a backoff\n"
                + "schedule alive behind your back.\n\n"
                + "A per-request timeout overrides the client's for that call only.");
    }
}
