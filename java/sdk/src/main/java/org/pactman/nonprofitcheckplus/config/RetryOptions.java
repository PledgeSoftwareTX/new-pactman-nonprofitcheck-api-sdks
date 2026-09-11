package org.pactman.nonprofitcheckplus.config;

import java.util.Arrays;
import java.util.Collections;
import java.util.LinkedHashSet;
import java.util.Set;
import org.pactman.nonprofitcheckplus.exceptions.PactmanConfigurationException;

/**
 * Retry policy. Applied per request, on top of the overall timeout.
 *
 * <p>Immutable. Start from {@link #defaults()} or {@link #builder()}, and use
 * {@link #toBuilder()} to change one setting without restating the rest.
 */
public final class RetryOptions {

    /**
     * Statuses that are never retried, whatever {@link #retryableStatuses()}
     * contains.
     *
     * <p>A rejected key, a forbidden resource, a malformed request and a missing
     * record all fail the same way on the second attempt, and retrying them
     * spends quota to learn nothing.
     */
    private static final Set<Integer> NEVER_RETRY_STATUSES =
            Collections.unmodifiableSet(new LinkedHashSet<>(Arrays.asList(400, 401, 403, 404)));

    private static final RetryOptions DEFAULTS = new Builder().build();

    private final int maxRetries;
    private final long initialDelayMs;
    private final long maxDelayMs;
    private final double backoffFactor;
    private final boolean jitter;
    private final Set<Integer> retryableStatuses;
    private final boolean respectRetryAfter;

    private RetryOptions(Builder builder) {
        this.maxRetries = builder.maxRetries;
        this.initialDelayMs = builder.initialDelayMs;
        this.maxDelayMs = builder.maxDelayMs;
        this.backoffFactor = builder.backoffFactor;
        this.jitter = builder.jitter;
        this.retryableStatuses =
                Collections.unmodifiableSet(new LinkedHashSet<>(builder.retryableStatuses));
        this.respectRetryAfter = builder.respectRetryAfter;
    }

    /**
     * The default policy: two retries, 500 ms of backoff growing by two, full
     * jitter, capped at eight seconds.
     *
     * @return the defaults.
     */
    public static RetryOptions defaults() {
        return DEFAULTS;
    }

    /**
     * A policy that never retries.
     *
     * @return the defaults with retrying switched off.
     */
    public static RetryOptions disabled() {
        return DEFAULTS.toBuilder().maxRetries(0).build();
    }

    /**
     * Starts building a policy from the defaults.
     *
     * @return a new builder.
     */
    public static Builder builder() {
        return new Builder();
    }

    /**
     * Starts building a policy from this one.
     *
     * @return a builder holding this policy's settings.
     */
    public Builder toBuilder() {
        return new Builder(this);
    }

    /**
     * Retries after the first attempt. Zero disables retrying.
     *
     * @return the retry count. Defaults to 2, which is three attempts in total.
     */
    public int maxRetries() {
        return maxRetries;
    }

    /**
     * Delay before the first retry.
     *
     * @return the delay in milliseconds. Defaults to 500.
     */
    public long initialDelayMs() {
        return initialDelayMs;
    }

    /**
     * Ceiling for a single backoff delay.
     *
     * <p>A server-supplied {@code Retry-After} is honored even when it exceeds this.
     *
     * @return the ceiling in milliseconds. Defaults to 8000.
     */
    public long maxDelayMs() {
        return maxDelayMs;
    }

    /**
     * How much each delay grows over the last.
     *
     * @return the factor. Defaults to 2.
     */
    public double backoffFactor() {
        return backoffFactor;
    }

    /**
     * Whether each delay is randomized across {@code [0, computed]} (full
     * jitter), so that clients failing together do not retry in lockstep.
     *
     * @return whether jitter is applied. Defaults to true.
     */
    public boolean jitter() {
        return jitter;
    }

    /**
     * HTTP statuses worth retrying.
     *
     * <p>Authentication, authorization, validation and not-found responses are
     * never retried, whatever this contains.
     *
     * @return the statuses. Defaults to 429, 500, 502, 503 and 504.
     */
    public Set<Integer> retryableStatuses() {
        return retryableStatuses;
    }

    /**
     * Whether to wait for the server's {@code Retry-After} before falling back
     * to backoff.
     *
     * @return whether {@code Retry-After} wins. Defaults to true.
     */
    public boolean respectRetryAfter() {
        return respectRetryAfter;
    }

    /**
     * Whether a status may be retried under this policy.
     *
     * @param status the HTTP status code.
     * @return whether another attempt is allowed for this status.
     */
    public boolean isRetryableStatus(int status) {
        return !NEVER_RETRY_STATUSES.contains(status) && retryableStatuses.contains(status);
    }

    /** Collects retry settings. */
    public static final class Builder {
        private int maxRetries = 2;
        private long initialDelayMs = 500L;
        private long maxDelayMs = 8_000L;
        private double backoffFactor = 2.0d;
        private boolean jitter = true;
        private Set<Integer> retryableStatuses =
                new LinkedHashSet<>(Arrays.asList(429, 500, 502, 503, 504));
        private boolean respectRetryAfter = true;

        private Builder() {
        }

        private Builder(RetryOptions source) {
            this.maxRetries = source.maxRetries;
            this.initialDelayMs = source.initialDelayMs;
            this.maxDelayMs = source.maxDelayMs;
            this.backoffFactor = source.backoffFactor;
            this.jitter = source.jitter;
            this.retryableStatuses = new LinkedHashSet<>(source.retryableStatuses);
            this.respectRetryAfter = source.respectRetryAfter;
        }

        /**
         * Sets how many retries follow the first attempt.
         *
         * @param value zero or more.
         * @return this builder.
         */
        public Builder maxRetries(int value) {
            this.maxRetries = value;
            return this;
        }

        /**
         * Sets the delay before the first retry.
         *
         * @param value milliseconds, zero or more.
         * @return this builder.
         */
        public Builder initialDelayMs(long value) {
            this.initialDelayMs = value;
            return this;
        }

        /**
         * Sets the ceiling for a single backoff delay.
         *
         * @param value milliseconds, zero or more.
         * @return this builder.
         */
        public Builder maxDelayMs(long value) {
            this.maxDelayMs = value;
            return this;
        }

        /**
         * Sets how much each delay grows over the last.
         *
         * @param value one or more.
         * @return this builder.
         */
        public Builder backoffFactor(double value) {
            this.backoffFactor = value;
            return this;
        }

        /**
         * Sets whether delays are randomized.
         *
         * @param value whether to apply full jitter.
         * @return this builder.
         */
        public Builder jitter(boolean value) {
            this.jitter = value;
            return this;
        }

        /**
         * Sets which statuses are worth retrying.
         *
         * @param values the statuses. Never-retried statuses stay never-retried.
         * @return this builder.
         */
        public Builder retryableStatuses(Set<Integer> values) {
            this.retryableStatuses = values == null
                    ? new LinkedHashSet<Integer>()
                    : new LinkedHashSet<>(values);
            return this;
        }

        /**
         * Sets whether the server's {@code Retry-After} wins over backoff.
         *
         * @param value whether to honor the header.
         * @return this builder.
         */
        public Builder respectRetryAfter(boolean value) {
            this.respectRetryAfter = value;
            return this;
        }

        /**
         * Validates and builds the policy.
         *
         * @return the immutable policy.
         * @throws PactmanConfigurationException if a setting is nonsensical.
         */
        public RetryOptions build() {
            if (maxRetries < 0) {
                throw new PactmanConfigurationException(
                        "`retry.maxRetries` must be 0 or more.");
            }

            if (initialDelayMs < 0) {
                throw new PactmanConfigurationException(
                        "`retry.initialDelayMs` must be 0 or more.");
            }

            if (maxDelayMs < 0) {
                throw new PactmanConfigurationException("`retry.maxDelayMs` must be 0 or more.");
            }

            if (!(backoffFactor >= 1.0d) || Double.isInfinite(backoffFactor)) {
                throw new PactmanConfigurationException(
                        "`retry.backoffFactor` must be a finite number of 1 or more.");
            }

            return new RetryOptions(this);
        }
    }
}
