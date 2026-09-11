package org.pactman.nonprofitcheckplus.examples.cases;

import org.pactman.nonprofitcheckplus.config.PactmanClientOptions;
import org.pactman.nonprofitcheckplus.config.RetryOptions;
import org.pactman.nonprofitcheckplus.devtools.FixtureEins;
import org.pactman.nonprofitcheckplus.examples.support.Example;
import org.pactman.nonprofitcheckplus.examples.support.ExampleContext;
import org.pactman.nonprofitcheckplus.examples.support.ExampleFailedException;
import org.pactman.nonprofitcheckplus.examples.support.Output;
import org.pactman.nonprofitcheckplus.exceptions.PactmanRateLimitException;

/**
 * EX-22 — Rate limiting.
 *
 * <p>HTTP 429 arrives as {@link PactmanRateLimitException} carrying the server's
 * {@code Retry-After}. With retries on, the SDK waits that long rather than
 * applying its own backoff; with them off, the header is yours to act on.
 */
public final class Ex22RateLimit implements Example {

    @Override
    public String id() {
        return "ex-22";
    }

    @Override
    public String title() {
        return "HTTP 429, Retry-After, and a client-side ceiling";
    }

    @Override
    public void run(String[] args) {
        // Retrying is switched off so the 429 surfaces instead of being absorbed
        // — this example is about reading it.
        try (ExampleContext context = ExampleContext.withFixtures(
                PactmanClientOptions.builder().retry(RetryOptions.disabled()))) {

            Output.heading("A 429, surfaced rather than retried");

            try {
                context.client().nonprofits().check(FixtureEins.CONTROL_RATE_LIMITED);
                throw new ExampleFailedException("Expected the API to report a rate limit.");
            } catch (PactmanRateLimitException failure) {
                Output.field("exception", failure.getClass().getSimpleName());
                Output.field("category", failure.category());
                Output.field("status", failure.status());
                Output.field("retryAfterSeconds", failure.retryAfterSeconds());
                Output.field("attempts", failure.attempts());
                Output.field("requestId", failure.requestId());
            }
        }

        // With retries enabled, the same request succeeds after the SDK has
        // waited the server's Retry-After. That is the default; nothing here
        // needs configuring for it.
        Output.heading("A client-side ceiling, off by default");
        Output.field(
                "maxRequestsPerSecond",
                "PactmanClientOptions.builder().maxRequestsPerSecond(3)");

        Output.note("The server's limits are authoritative and can change; a client-side\n"
                + "ceiling is a courtesy, not a guarantee, and it only spaces requests made\n"
                + "through one client instance. Share one client across your application, or\n"
                + "each caller gets its own throttle and the total is unbounded.\n\n"
                + "For volume, prefer one bulk request over fifty concurrent single checks.");
    }
}
