package org.pactman.nonprofitcheckplus.examples.support;

import java.io.IOException;
import org.pactman.nonprofitcheckplus.PactmanClient;
import org.pactman.nonprofitcheckplus.config.PactmanClientOptions;
import org.pactman.nonprofitcheckplus.config.RetryOptions;
import org.pactman.nonprofitcheckplus.devtools.FixtureApi;

/**
 * Wiring shared by every example: where to send requests, and where the key
 * comes from.
 *
 * <p>Examples that need an ordinary lookup use {@link #live()} and run against
 * production, or against {@code PACTMAN_BASE_URL} when it is set. Examples that
 * need a record or a response a live API will not produce on request — a revoked
 * exemption, an OFAC match, an HTTP 429, a field newer than this SDK — use
 * {@link #withFixtures()}, which starts the bundled fixture API and shuts it
 * down on the way out.
 */
public final class ExampleContext implements AutoCloseable {

    private final PactmanClient client;
    private final FixtureApi fixtures;

    private ExampleContext(PactmanClient client, FixtureApi fixtures) {
        this.client = client;
        this.fixtures = fixtures;
    }

    /**
     * The client this example sends through.
     *
     * @return the client.
     */
    public PactmanClient client() {
        return client;
    }

    /**
     * Whether this example is running against the bundled fixture API.
     *
     * @return true when the records come from fixtures.
     */
    public boolean usesFixtures() {
        return fixtures != null;
    }

    /**
     * A client pointed at production, or at {@code PACTMAN_BASE_URL} when set.
     *
     * @return a context to close when the example finishes.
     */
    public static ExampleContext live() {
        return live(PactmanClientOptions.builder());
    }

    /**
     * A client pointed at production, with options the example wants to show.
     *
     * @param options a builder the example has already configured. The key and
     *                base URL are filled in here.
     * @return a context to close when the example finishes.
     */
    public static ExampleContext live(PactmanClientOptions.Builder options) {
        options.apiKey(requireApiKey());
        String override = baseUrlOverride();

        if (override != null) {
            options.baseUrl(override);
        }

        return new ExampleContext(new PactmanClient(options.build()), null);
    }

    /**
     * A client pointed at the bundled fixture API.
     *
     * <p>{@code PACTMAN_BASE_URL} still wins, so the same example can be aimed
     * at a different mock or a sandbox you have been given — and so the smoke
     * runner can point every example at one shared server instead of thirty.
     *
     * @return a context to close when the example finishes.
     */
    public static ExampleContext withFixtures() {
        return withFixtures(PactmanClientOptions.builder());
    }

    /**
     * A client pointed at the bundled fixture API, with options the example
     * wants to show.
     *
     * @param options a builder the example has already configured.
     * @return a context to close when the example finishes.
     */
    public static ExampleContext withFixtures(PactmanClientOptions.Builder options) {
        String override = baseUrlOverride();

        if (override != null) {
            return new ExampleContext(
                    new PactmanClient(options.apiKey(requireApiKey()).baseUrl(override).build()),
                    null);
        }

        FixtureApi fixtures;

        try {
            fixtures = FixtureApi.start("fixture-key");
        } catch (IOException unavailable) {
            throw new IllegalStateException("could not start the fixture API", unavailable);
        }

        System.out.println("Using the bundled fixture API at " + fixtures.baseUrl()
                + " — these scenarios need");
        System.out.println("records and responses a live API will not produce on request.");

        return new ExampleContext(
                new PactmanClient(
                        options.apiKey(fixtures.apiKey()).baseUrl(fixtures.baseUrl()).build()),
                fixtures);
    }

    /**
     * A retry policy with the delays shortened, so an example that demonstrates
     * retrying does not spend the default backoff waiting.
     *
     * @param maxRetries how many retries to allow.
     * @return the policy.
     */
    public static RetryOptions quickRetries(int maxRetries) {
        return RetryOptions.builder()
                .maxRetries(maxRetries)
                .initialDelayMs(50)
                .maxDelayMs(400)
                .build();
    }

    /**
     * The API key, or an explanation and an exit.
     *
     * <p>The key is never printed, embedded in a message, or written to a file.
     *
     * @return the key.
     */
    public static String requireApiKey() {
        String apiKey = System.getProperty("pactman.apiKey", System.getenv("PACTMAN_API_KEY"));

        if (apiKey == null || apiKey.trim().isEmpty()) {
            System.err.println("Set PACTMAN_API_KEY before running this example.");
            System.err.println(
                    "Load it from your secret manager or a .env file excluded from git.");
            System.exit(1);
        }

        return apiKey;
    }

    /**
     * An explicit host to use instead of production, when one is configured.
     *
     * @return the base URL, or {@code null}.
     */
    public static String baseUrlOverride() {
        String override =
                System.getProperty("pactman.baseUrl", System.getenv("PACTMAN_BASE_URL"));

        return override == null || override.trim().isEmpty() ? null : override.trim();
    }

    @Override
    public void close() {
        client.close();

        if (fixtures != null) {
            fixtures.close();
        }
    }
}
