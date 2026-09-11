package org.pactman.nonprofitcheckplus;

import java.util.Map;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.SynchronousQueue;
import java.util.concurrent.ThreadPoolExecutor;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicLong;
import org.pactman.nonprofitcheckplus.config.ClientConfig;
import org.pactman.nonprofitcheckplus.config.PactmanClientOptions;
import org.pactman.nonprofitcheckplus.config.ConfigResolver;
import org.pactman.nonprofitcheckplus.config.RetryOptions;
import org.pactman.nonprofitcheckplus.http.Transport;
import org.pactman.nonprofitcheckplus.http.TransportHooks;

/**
 * Entry point for the SDK.
 *
 * <p>Server-side use only. The API key is a private credential; do not construct
 * this client in a mobile binary, a desktop application, or any other context
 * where the artifact is shipped to a user.
 *
 * <p>Thread-safe and designed to be long-lived: build one per application and
 * share it, so connections and the rate limiter are shared too.
 *
 * <pre>{@code
 * try (PactmanClient client = new PactmanClient(System.getenv("PACTMAN_API_KEY"))) {
 *     SingleCheckResult result = client.nonprofits().check("41-1787097");
 * }
 * }</pre>
 *
 * <p>{@link #close()} only shuts down the thread pool the async methods use, and
 * only if they were used; a client that is never closed leaks nothing when no
 * async call was made.
 */
public final class PactmanClient implements AutoCloseable {

    private final ClientConfig config;
    private final Transport transport;
    private final NonprofitsResource nonprofits;

    /** Created on first async use, so the common case allocates no threads. */
    private volatile ExecutorService executor;

    private final Object executorLock = new Object();

    /**
     * Builds a client with every default, from an API key.
     *
     * @param apiKey your Pactman API key.
     */
    public PactmanClient(String apiKey) {
        this(PactmanClientOptions.of(apiKey));
    }

    /**
     * Builds a client.
     *
     * @param options the configuration. The API key is required.
     * @throws org.pactman.nonprofitcheckplus.exceptions.PactmanConfigurationException
     *         if the options are unusable.
     */
    public PactmanClient(PactmanClientOptions options) {
        this(options, null);
    }

    /**
     * Builds a client with a substituted clock and random source.
     *
     * <p>The seam the test suite uses to assert on retry delays without waiting
     * them. It is not covered by semantic versioning; do not depend on it.
     *
     * @param options the configuration. The API key is required.
     * @param hooks   the clock and random source, or {@code null} for the real ones.
     */
    public PactmanClient(PactmanClientOptions options, TransportHooks hooks) {
        ConfigResolver.Resolved resolved = ConfigResolver.resolve(options);
        this.config = resolved.config();
        this.transport = new Transport(resolved.apiKey(), this.config, hooks);
        this.nonprofits = new NonprofitsResource(this.transport, this::runAsync);
    }

    /**
     * Nonprofit lookups.
     *
     * @return the resource.
     */
    public NonprofitsResource nonprofits() {
        return nonprofits;
    }

    /**
     * The resolved base URL every request is sent to.
     *
     * @return the base URL.
     */
    public String baseUrl() {
        return config.baseUrl();
    }

    /**
     * The named environment in use.
     *
     * @return the environment, or {@code null} when an explicit base URL was given.
     */
    public PactmanEnvironment environment() {
        return config.environment();
    }

    /**
     * The resolved timeout.
     *
     * @return the timeout in milliseconds.
     */
    public long timeoutMs() {
        return config.timeoutMs();
    }

    /**
     * The resolved retry policy.
     *
     * <p>Start from this when overriding one setting for a single request:
     * {@code client.retry().toBuilder().maxRetries(0).build()}.
     *
     * @return the policy.
     */
    public RetryOptions retry() {
        return config.retry();
    }

    /**
     * A redacted view of the configuration.
     *
     * <p>The API key is not a property of this object and never appears here or
     * in {@link #toString()}.
     *
     * @return the settings, in a stable order.
     */
    public Map<String, Object> toMap() {
        return config.toMap();
    }

    /**
     * Releases the thread pool the async methods use.
     *
     * <p>In-flight async calls are interrupted. Nothing else is held: the HTTP
     * client, if this SDK built one, is released with the client itself.
     */
    @Override
    public void close() {
        ExecutorService running = executor;

        if (running != null) {
            running.shutdownNow();
        }
    }

    @Override
    public String toString() {
        return "PactmanClient(" + config.baseUrl() + ")";
    }

    private void runAsync(Runnable work) {
        executor().execute(work);
    }

    private ExecutorService executor() {
        ExecutorService running = executor;

        if (running != null) {
            return running;
        }

        synchronized (executorLock) {
            if (executor == null) {
                executor = newExecutor();
            }

            return executor;
        }
    }

    /**
     * An unbounded pool of daemon threads that retire when idle.
     *
     * <p>The work is blocking I/O, so it must not run on the common
     * ForkJoinPool — a batch of lookups there would starve every other parallel
     * stream in the application. Daemon threads keep a client the caller forgot
     * to close from holding the JVM open.
     */
    private static ExecutorService newExecutor() {
        AtomicLong counter = new AtomicLong();

        return new ThreadPoolExecutor(
                0,
                Integer.MAX_VALUE,
                60L,
                TimeUnit.SECONDS,
                new SynchronousQueue<Runnable>(),
                runnable -> {
                    Thread thread = Executors.defaultThreadFactory().newThread(runnable);
                    thread.setName("pactman-nonprofit-check-" + counter.incrementAndGet());
                    thread.setDaemon(true);

                    return thread;
                });
    }
}
