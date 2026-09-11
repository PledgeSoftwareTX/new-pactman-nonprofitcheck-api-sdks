package org.pactman.nonprofitcheckplus.config;

import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.Map;
import org.pactman.nonprofitcheckplus.PactmanEnvironment;
import org.pactman.nonprofitcheckplus.http.HttpExchange;

/**
 * Fully-resolved configuration.
 *
 * <p>The API key is deliberately not here. It is held by the transport and
 * written into the {@code Authorization} header at send time, so no diagnostic
 * view of the configuration can leak it.
 */
public final class ClientConfig {

    private final String baseUrl;
    private final PactmanEnvironment environment;
    private final long timeoutMs;
    private final RetryOptions retry;
    private final Double maxRequestsPerSecond;
    private final Map<String, String> defaultHeaders;
    private final String userAgent;
    private final HttpExchange httpExchange;

    /**
     * Creates the resolved configuration.
     *
     * @param baseUrl              the base URL every request is sent to.
     * @param environment          the named environment, or {@code null} when an
     *                             explicit base URL was given.
     * @param timeoutMs            the overall timeout per attempt.
     * @param retry                the retry policy.
     * @param maxRequestsPerSecond the client-side rate ceiling, or {@code null} when off.
     * @param defaultHeaders       headers sent with every request.
     * @param userAgent            the {@code User-Agent} this client sends.
     * @param httpExchange         the HTTP layer to send through.
     */
    public ClientConfig(
            String baseUrl,
            PactmanEnvironment environment,
            long timeoutMs,
            RetryOptions retry,
            Double maxRequestsPerSecond,
            Map<String, String> defaultHeaders,
            String userAgent,
            HttpExchange httpExchange) {
        this.baseUrl = baseUrl;
        this.environment = environment;
        this.timeoutMs = timeoutMs;
        this.retry = retry;
        this.maxRequestsPerSecond = maxRequestsPerSecond;
        this.defaultHeaders = Collections.unmodifiableMap(
                new LinkedHashMap<>(defaultHeaders == null
                        ? Collections.<String, String>emptyMap()
                        : defaultHeaders));
        this.userAgent = userAgent;
        this.httpExchange = httpExchange;
    }

    /**
     * The base URL every request is sent to.
     *
     * @return an absolute URL with no trailing slash.
     */
    public String baseUrl() {
        return baseUrl;
    }

    /**
     * The named environment in use.
     *
     * @return the environment, or {@code null} when an explicit base URL was given.
     */
    public PactmanEnvironment environment() {
        return environment;
    }

    /**
     * The overall timeout per attempt.
     *
     * @return the timeout in milliseconds.
     */
    public long timeoutMs() {
        return timeoutMs;
    }

    /**
     * The resolved retry policy.
     *
     * @return the policy.
     */
    public RetryOptions retry() {
        return retry;
    }

    /**
     * The client-side ceiling on outbound requests per second.
     *
     * @return the ceiling, or {@code null} when off.
     */
    public Double maxRequestsPerSecond() {
        return maxRequestsPerSecond;
    }

    /**
     * Headers sent with every request.
     *
     * @return the headers.
     */
    public Map<String, String> defaultHeaders() {
        return defaultHeaders;
    }

    /**
     * The {@code User-Agent} this client sends.
     *
     * @return the user agent string.
     */
    public String userAgent() {
        return userAgent;
    }

    /**
     * The HTTP layer requests are sent through.
     *
     * @return the exchange.
     */
    public HttpExchange httpExchange() {
        return httpExchange;
    }

    /**
     * A redacted view of this configuration.
     *
     * <p>The API key is not a property of this object and never appears here.
     *
     * @return the settings, in a stable order.
     */
    public Map<String, Object> toMap() {
        Map<String, Object> fields = new LinkedHashMap<>();
        fields.put("baseUrl", baseUrl);
        fields.put("environment", environment == null ? null : environment.environmentName());
        fields.put("timeoutMs", timeoutMs);
        fields.put("maxRetries", retry.maxRetries());
        fields.put("maxRequestsPerSecond", maxRequestsPerSecond);
        fields.put("userAgent", userAgent);
        fields.put("apiKey", "[redacted]");

        return fields;
    }
}
