package org.pactman.nonprofitcheckplus.examples.cases;

import org.pactman.nonprofitcheckplus.config.PactmanClientOptions;
import org.pactman.nonprofitcheckplus.config.RetryOptions;
import org.pactman.nonprofitcheckplus.devtools.FixtureEins;
import org.pactman.nonprofitcheckplus.examples.support.Example;
import org.pactman.nonprofitcheckplus.examples.support.ExampleContext;
import org.pactman.nonprofitcheckplus.examples.support.ExampleFailedException;
import org.pactman.nonprofitcheckplus.examples.support.Output;
import org.pactman.nonprofitcheckplus.exceptions.PactmanAuthenticationException;
import org.pactman.nonprofitcheckplus.models.SingleCheckResult;

/**
 * EX-23 — Retrying transient failures.
 *
 * <p>A 503 that clears on the next attempt should not reach your error handler.
 * A rejected key should reach it immediately, because it will still be rejected
 * on the third attempt.
 */
public final class Ex23TransientRetries implements Example {

    @Override
    public String id() {
        return "ex-23";
    }

    @Override
    public String title() {
        return "What gets retried, and what never does";
    }

    @Override
    public void run(String[] args) {
        // Short delays so the example does not spend the default backoff
        // waiting. The defaults — 500ms growing by two, with full jitter — are
        // right for production.
        try (ExampleContext context = ExampleContext.withFixtures(
                PactmanClientOptions.builder().retry(ExampleContext.quickRetries(3)))) {

            Output.heading("Two 503s, then a success");

            long started = System.currentTimeMillis();
            SingleCheckResult result =
                    context.client().nonprofits().check(FixtureEins.CONTROL_TRANSIENT_FAILURE);

            Output.field("organization", result.getNonprofit().getOrganizationName());
            Output.field("HTTP status", result.getStatus());
            Output.field("wall clock", (System.currentTimeMillis() - started) + "ms");
            Output.bullet("The caller never saw the two failures.");
        }

        Output.heading("A rejected key is not retried");

        try (ExampleContext context = ExampleContext.withFixtures()) {
            String badKeyUrl = context.client().baseUrl();

            try (org.pactman.nonprofitcheckplus.PactmanClient client =
                    new org.pactman.nonprofitcheckplus.PactmanClient(
                            PactmanClientOptions.builder()
                                    .apiKey("not-the-right-key")
                                    .baseUrl(badKeyUrl)
                                    .retry(ExampleContext.quickRetries(3))
                                    .build())) {

                long started = System.currentTimeMillis();

                try {
                    client.nonprofits().check(FixtureEins.PUBLIC_CHARITY);
                    throw new ExampleFailedException("Expected the key to be rejected.");
                } catch (PactmanAuthenticationException failure) {
                    Output.field("exception", failure.getClass().getSimpleName());
                    Output.field("attempts", failure.attempts());
                    Output.field("wall clock", (System.currentTimeMillis() - started) + "ms");

                    if (failure.attempts() != 1) {
                        throw new ExampleFailedException(
                                "A 401 should be attempted exactly once, was " + failure.attempts());
                    }
                }
            }
        }

        Output.note("Retried: 429, 500, 502, 503, 504, and transient network failures.\n"
                + "Never retried: 400, 401, 403, 404 — whatever retryableStatuses says.\n\n"
                + "The reason is quota. A request that cannot succeed on the first attempt\n"
                + "cannot succeed on the third either, and each one costs. Backoff is jittered\n"
                + "by default so that clients failing together do not retry in lockstep and\n"
                + "turn a blip into an outage.");
    }
}
