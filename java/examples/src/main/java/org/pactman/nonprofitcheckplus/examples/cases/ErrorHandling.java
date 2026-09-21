package org.pactman.nonprofitcheckplus.examples.cases;

import java.util.Collections;
import java.util.stream.Collectors;
import org.pactman.nonprofitcheckplus.PactmanClient;
import org.pactman.nonprofitcheckplus.config.PactmanClientOptions;
import org.pactman.nonprofitcheckplus.config.RetryOptions;
import org.pactman.nonprofitcheckplus.examples.support.Example;
import org.pactman.nonprofitcheckplus.examples.support.ExampleContext;
import org.pactman.nonprofitcheckplus.examples.support.ExampleFailedException;
import org.pactman.nonprofitcheckplus.exceptions.PactmanApiException;
import org.pactman.nonprofitcheckplus.exceptions.PactmanAuthenticationException;
import org.pactman.nonprofitcheckplus.exceptions.PactmanNetworkException;
import org.pactman.nonprofitcheckplus.exceptions.PactmanRateLimitException;
import org.pactman.nonprofitcheckplus.exceptions.PactmanTimeoutException;
import org.pactman.nonprofitcheckplus.exceptions.PactmanValidationException;
import org.pactman.nonprofitcheckplus.exceptions.ValidationIssue;
import org.pactman.nonprofitcheckplus.models.SingleCheckResult;

/**
 * Branching on error type: local validation, authentication, and rate limits.
 */
public final class ErrorHandling implements Example {

    @Override
    public String id() {
        return "error-handling";
    }

    @Override
    public String title() {
        return "Branching on error type, with no string parsing";
    }

    @Override
    public void run(String[] args) {
        try (ExampleContext context = ExampleContext.withFixtures(
                PactmanClientOptions.builder()
                        .timeoutMs(10_000)
                        .retry(RetryOptions.builder().maxRetries(2).build()))) {
            PactmanClient client = context.client();

            // 1. A malformed EIN never leaves the process.
            try {
                client.nonprofits().check("41178709");
                System.out.println("malformed EIN -> unexpectedly succeeded");
            } catch (RuntimeException error) {
                System.out.println("malformed EIN -> " + explain(error));
            }

            // 2. An empty batch is rejected locally too.
            try {
                client.nonprofits().checkBulk(Collections.emptyList());
                System.out.println("empty batch   -> unexpectedly succeeded");
            } catch (RuntimeException error) {
                System.out.println("empty batch   -> " + explain(error));
            }

            // 3. A bad key produces an authentication error on first use.
            try (PactmanClient badClient = new PactmanClient(PactmanClientOptions.builder()
                    .apiKey("obviously-not-a-real-key")
                    .baseUrl(client.baseUrl())
                    .retry(RetryOptions.disabled())
                    .build())) {
                badClient.nonprofits().check("411787097");
                throw new ExampleFailedException("A rejected key should not have succeeded.");
            } catch (PactmanAuthenticationException error) {
                System.out.println("bad key       -> " + explain(error));
            }

            // 4. A real call, handled the same way.
            try {
                SingleCheckResult result = client.nonprofits().check("41-1787097");

                System.out.println("valid check   -> " + (result.getNonprofit() == null
                        ? "no record"
                        : result.getNonprofit().getOrganizationName()));
            } catch (RuntimeException error) {
                System.out.println("valid check   -> " + explain(error));
            }
        }
    }

    /** One place to turn any SDK failure into an action. No string parsing. */
    private static String explain(RuntimeException error) {
        if (error instanceof PactmanValidationException) {
            PactmanValidationException invalid = (PactmanValidationException) error;
            String detail = invalid.issues().isEmpty()
                    ? invalid.getMessage()
                    : invalid.issues().stream()
                            .map(ValidationIssue::message)
                            .collect(Collectors.joining(" "));

            return "Local validation — fix the input. " + detail;
        }

        if (error instanceof PactmanAuthenticationException) {
            return "Authentication — the API key was rejected. Check PACTMAN_API_KEY.";
        }

        if (error instanceof PactmanRateLimitException) {
            Double retryAfter = ((PactmanRateLimitException) error).retryAfterSeconds();

            return "Rate limited — retry after "
                    + (retryAfter == null ? "an unspecified" : retryAfter) + " seconds.";
        }

        if (error instanceof PactmanTimeoutException) {
            return "Timed out after " + ((PactmanTimeoutException) error).timeoutMs()
                    + "ms — raise timeoutMs or retry later.";
        }

        if (error instanceof PactmanNetworkException) {
            return "Network failure — the request never reached the API.";
        }

        if (error instanceof PactmanApiException) {
            PactmanApiException api = (PactmanApiException) error;

            return "API error " + api.status() + " (request "
                    + (api.requestId() == null ? "unknown" : api.requestId()) + "): "
                    + api.getMessage();
        }

        return "Unexpected: " + error;
    }
}
