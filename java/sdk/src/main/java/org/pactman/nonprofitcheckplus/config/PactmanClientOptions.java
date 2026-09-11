package org.pactman.nonprofitcheckplus.config;

import java.net.http.HttpClient;
import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.Map;
import org.pactman.nonprofitcheckplus.PactmanEnvironment;
import org.pactman.nonprofitcheckplus.http.HttpExchange;

/**
 * Options accepted by the
 * {@link org.pactman.nonprofitcheckplus.PactmanClient} constructor.
 *
 * <pre>{@code
 * PactmanClientOptions options = PactmanClientOptions.builder()
 *         .apiKey(System.getenv("PACTMAN_API_KEY"))
 *         .timeoutMs(10_000)
 *         .build();
 * }</pre>
 */
public final class PactmanClientOptions {

    /** Default overall timeout per attempt, in milliseconds. */
    public static final long DEFAULT_TIMEOUT_MS = 30_000L;

    private final String apiKey;
    private final PactmanEnvironment environment;
    private final String baseUrl;
    private final Long timeoutMs;
    private final RetryOptions retry;
    private final Double maxRequestsPerSecond;
    private final Map<String, String> defaultHeaders;
    private final HttpClient httpClient;
    private final HttpExchange httpExchange;

    private PactmanClientOptions(Builder builder) {
        this.apiKey = builder.apiKey;
        this.environment = builder.environment;
        this.baseUrl = builder.baseUrl;
        this.timeoutMs = builder.timeoutMs;
        this.retry = builder.retry;
        this.maxRequestsPerSecond = builder.maxRequestsPerSecond;
        this.defaultHeaders =
                Collections.unmodifiableMap(new LinkedHashMap<>(builder.defaultHeaders));
        this.httpClient = builder.httpClient;
        this.httpExchange = builder.httpExchange;
    }

    /**
     * Starts building options.
     *
     * @return a new builder.
     */
    public static Builder builder() {
        return new Builder();
    }

    /**
     * Options carrying nothing but an API key.
     *
     * @param apiKey the Pactman API key.
     * @return options using every default.
     */
    public static PactmanClientOptions of(String apiKey) {
        return builder().apiKey(apiKey).build();
    }

    /**
     * Your Pactman API key.
     *
     * @return the key as supplied, or {@code null} when none was set.
     */
    public String apiKey() {
        return apiKey;
    }

    /**
     * The named Pactman environment.
     *
     * @return the environment, or {@code null} to use the default.
     */
    public PactmanEnvironment environment() {
        return environment;
    }

    /**
     * An explicit base URL, overriding {@link #environment()} when set.
     *
     * @return the base URL, or {@code null}.
     */
    public String baseUrl() {
        return baseUrl;
    }

    /**
     * Overall timeout per attempt.
     *
     * @return the timeout in milliseconds, or {@code null} to use the default.
     */
    public Long timeoutMs() {
        return timeoutMs;
    }

    /**
     * The retry policy.
     *
     * @return the policy, or {@code null} to use the default.
     */
    public RetryOptions retry() {
        return retry;
    }

    /**
     * A client-side ceiling on outbound requests per second.
     *
     * @return the ceiling, or {@code null} when off.
     */
    public Double maxRequestsPerSecond() {
        return maxRequestsPerSecond;
    }

    /**
     * Extra headers sent with every request.
     *
     * @return the headers, in the order they were added.
     */
    public Map<String, String> defaultHeaders() {
        return defaultHeaders;
    }

    /**
     * The {@link HttpClient} to send with.
     *
     * @return the client, or {@code null} to build one.
     */
    public HttpClient httpClient() {
        return httpClient;
    }

    /**
     * The exchange to send through, replacing the built-in client entirely.
     *
     * @return the exchange, or {@code null}.
     */
    public HttpExchange httpExchange() {
        return httpExchange;
    }

    /** Collects client options. */
    public static final class Builder {
        private String apiKey;
        private PactmanEnvironment environment;
        private String baseUrl;
        private Long timeoutMs;
        private RetryOptions retry;
        private Double maxRequestsPerSecond;
        private final Map<String, String> defaultHeaders = new LinkedHashMap<>();
        private HttpClient httpClient;
        private HttpExchange httpExchange;

        private Builder() {
        }

        /**
         * Sets your Pactman API key.
         *
         * <p>Load it from the environment or a secret manager; never commit it,
         * and never ship it to a browser or a mobile binary.
         *
         * @param value the key. Required.
         * @return this builder.
         */
        public Builder apiKey(String value) {
            this.apiKey = value;
            return this;
        }

        /**
         * Sets the named Pactman environment.
         *
         * @param value the environment. Defaults to
         *              {@link PactmanEnvironment#PRODUCTION}.
         * @return this builder.
         */
        public Builder environment(PactmanEnvironment value) {
            this.environment = value;
            return this;
        }

        /**
         * Sets an explicit base URL, for a mock server, a proxy, or a host
         * Pactman has given you directly.
         *
         * <p>Overrides {@link #environment(PactmanEnvironment)} when set.
         *
         * @param value the base URL.
         * @return this builder.
         */
        public Builder baseUrl(String value) {
            this.baseUrl = value;
            return this;
        }

        /**
         * Sets the overall timeout per attempt.
         *
         * @param value milliseconds. Defaults to {@link #DEFAULT_TIMEOUT_MS}.
         * @return this builder.
         */
        public Builder timeoutMs(long value) {
            this.timeoutMs = value;
            return this;
        }

        /**
         * Sets the retry policy.
         *
         * @param value the policy, or {@link RetryOptions#disabled()} to stop retrying.
         * @return this builder.
         */
        public Builder retry(RetryOptions value) {
            this.retry = value;
            return this;
        }

        /**
         * Sets a client-side ceiling on outbound requests per second.
         *
         * <p>Off by default; the server's limits are authoritative and may change.
         *
         * @param value requests per second, greater than zero.
         * @return this builder.
         */
        public Builder maxRequestsPerSecond(double value) {
            this.maxRequestsPerSecond = value;
            return this;
        }

        /**
         * Adds a header sent with every request. Cannot override {@code Authorization}.
         *
         * @param name  the header name.
         * @param value the header value.
         * @return this builder.
         */
        public Builder defaultHeader(String name, String value) {
            if (name != null && value != null) {
                defaultHeaders.put(name, value);
            }

            return this;
        }

        /**
         * Sets the {@link HttpClient} to send with.
         *
         * <p>Use this to share an application's connection pool, proxy or TLS
         * configuration with the SDK. One is built if you do not supply one.
         *
         * @param value the client.
         * @return this builder.
         */
        public Builder httpClient(HttpClient value) {
            this.httpClient = value;
            return this;
        }

        /**
         * Replaces the HTTP layer entirely.
         *
         * <p>Takes precedence over {@link #httpClient(HttpClient)}. Timeouts,
         * retries and rate limiting still apply above it.
         *
         * @param value the exchange.
         * @return this builder.
         */
        public Builder httpExchange(HttpExchange value) {
            this.httpExchange = value;
            return this;
        }

        /**
         * Builds the options.
         *
         * @return an immutable snapshot.
         */
        public PactmanClientOptions build() {
            return new PactmanClientOptions(this);
        }
    }
}
