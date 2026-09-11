package org.pactman.nonprofitcheckplus.config;

import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.Map;

/**
 * Per-request overrides accepted by every public method.
 *
 * <p>Fluent and mutable: build one per call, or hold a configured instance and
 * pass it repeatedly — nothing here is read after the request is sent.
 *
 * <pre>{@code
 * RequestOptions options = new RequestOptions()
 *         .timeoutMs(5_000)
 *         .header("X-Correlation-Id", correlationId);
 * }</pre>
 *
 * <p>There is no cancellation token here. A blocking call is cancelled by
 * interrupting the calling thread, and an async call by cancelling the
 * {@link java.util.concurrent.CompletableFuture} it returned; both surface as a
 * {@link org.pactman.nonprofitcheckplus.exceptions.PactmanNetworkException}.
 */
public class RequestOptions {

    private Long timeoutMs;
    private RetryOptions retry;
    private final Map<String, String> headers = new LinkedHashMap<>();

    /** Creates options that override nothing. */
    public RequestOptions() {
    }

    /**
     * Overrides the client's timeout for this request.
     *
     * @param value the timeout in milliseconds.
     * @return these options.
     */
    public RequestOptions timeoutMs(long value) {
        this.timeoutMs = value;
        return this;
    }

    /**
     * Overrides the client's retry policy for this request.
     *
     * <p>Replaces the policy outright rather than merging into it. To change one
     * setting, start from the client's own policy:
     * {@code client.retry().toBuilder().maxRetries(0).build()}.
     *
     * @param value the policy, or {@link RetryOptions#disabled()} to stop retrying.
     * @return these options.
     */
    public RequestOptions retry(RetryOptions value) {
        this.retry = value;
        return this;
    }

    /**
     * Adds a header to this request. Cannot override {@code Authorization}.
     *
     * @param name  the header name.
     * @param value the header value.
     * @return these options.
     */
    public RequestOptions header(String name, String value) {
        if (name != null && value != null) {
            headers.put(name, value);
        }

        return this;
    }

    /**
     * The timeout override.
     *
     * @return the timeout in milliseconds, or {@code null} to use the client's.
     */
    public Long timeoutMs() {
        return timeoutMs;
    }

    /**
     * The retry policy override.
     *
     * @return the policy, or {@code null} to use the client's.
     */
    public RetryOptions retry() {
        return retry;
    }

    /**
     * The headers added for this request.
     *
     * @return the headers, in the order they were added.
     */
    public Map<String, String> headers() {
        return Collections.unmodifiableMap(headers);
    }
}
