package org.pactman.nonprofitcheckplus.http;

import java.net.URI;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.time.Instant;
import java.time.ZonedDateTime;
import java.time.format.DateTimeFormatter;
import java.time.format.DateTimeParseException;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.CompletionException;
import java.util.concurrent.ExecutionException;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.TimeoutException;
import org.pactman.nonprofitcheckplus.config.ClientConfig;
import org.pactman.nonprofitcheckplus.config.RequestOptions;
import org.pactman.nonprofitcheckplus.config.RetryOptions;
import org.pactman.nonprofitcheckplus.exceptions.ApiErrorInit;
import org.pactman.nonprofitcheckplus.exceptions.PactmanApiException;
import org.pactman.nonprofitcheckplus.exceptions.PactmanConfigurationException;
import org.pactman.nonprofitcheckplus.exceptions.PactmanException;
import org.pactman.nonprofitcheckplus.exceptions.PactmanNetworkException;
import org.pactman.nonprofitcheckplus.exceptions.PactmanTimeoutException;
import org.pactman.nonprofitcheckplus.internal.Json;
import org.pactman.nonprofitcheckplus.internal.JsonException;
import org.pactman.nonprofitcheckplus.models.ApiErrorDetail;
import org.pactman.nonprofitcheckplus.models.ResponseBody;

/**
 * HTTP transport: authentication headers, timeouts, cancellation, retries with
 * jittered backoff, {@code Retry-After} handling, and mapping responses to the
 * exception taxonomy.
 *
 * <p>The API key is written into the {@code Authorization} header at send time
 * and is never stored on a request record, an exception, or any diagnostic
 * output.
 */
public final class Transport {

    private final String apiKey;
    private final ClientConfig config;
    private final TransportHooks hooks;

    /** Guards {@link #nextRequestAtMs}; a client is shared across threads. */
    private final Object throttleLock = new Object();

    private long nextRequestAtMs;

    /**
     * Creates the transport.
     *
     * @param apiKey the validated API key.
     * @param config the resolved configuration.
     * @param hooks  the clock and random source, or {@code null} for the real ones.
     */
    public Transport(String apiKey, ClientConfig config, TransportHooks hooks) {
        this.apiKey = apiKey;
        this.config = config;
        this.hooks = hooks == null ? TransportHooks.DEFAULT : hooks;
    }

    /**
     * Sends a request, retrying under the resolved policy.
     *
     * @param method  {@code GET} or {@code POST}.
     * @param path    the path, already encoded, to append to the base URL.
     * @param body    the request body to serialize as JSON, or {@code null} for none.
     * @param options per-request overrides, or {@code null}.
     * @return the parsed response.
     * @throws PactmanApiException     when the API returns a status this SDK
     *                                 surfaces as an error.
     * @throws PactmanTimeoutException when an attempt exceeds the timeout and no
     *                                 retries remain.
     * @throws PactmanNetworkException when the request produces no response, or
     *                                 the caller cancels it.
     */
    public TransportResponse send(
            String method, String path, Object body, RequestOptions options) {
        RetryOptions retry = options != null && options.retry() != null
                ? options.retry()
                : config.retry();
        long timeoutMs = options != null && options.timeoutMs() != null
                ? options.timeoutMs()
                : config.timeoutMs();
        URI url = URI.create(config.baseUrl() + path);
        String payload = body == null ? null : Json.write(body);
        Map<String, String> headers = buildHeaders(options, payload != null);

        int attempt = 0;

        for (;;) {
            attempt += 1;
            throwIfCancelled(0);
            throttle();

            Attempt outcome = attempt(url, method, headers, payload, timeoutMs, attempt);

            if (outcome.response != null) {
                HttpResponse<String> response = outcome.response;
                Object parsed = parseBody(response.body());
                String requestId = readRequestId(response);

                if (response.statusCode() >= 200 && response.statusCode() < 300) {
                    return new TransportResponse(
                            response.statusCode(),
                            requestId,
                            new ResponseBody(asFields(parsed)),
                            attempt);
                }

                Double retryAfterSeconds = readRetryAfter(
                        response.headers().firstValue("retry-after").orElse(null), Instant.now());

                PactmanApiException apiError = PactmanApiException.fromStatus(
                        buildApiErrorInit(
                                response.statusCode(), parsed, requestId, retryAfterSeconds, attempt));

                if (attempt > retry.maxRetries()
                        || !retry.isRetryableStatus(response.statusCode())) {
                    throw apiError;
                }

                waitBeforeRetry(attempt, retry, retryAfterSeconds);
                continue;
            }

            // A timeout or a transport failure.
            if (attempt > retry.maxRetries() || outcome.cancelled) {
                throw outcome.error;
            }

            waitBeforeRetry(attempt, retry, null);
        }
    }

    /** Header names this SDK owns; a caller's value for one of these is dropped. */
    private static final List<String> RESERVED_HEADERS =
            java.util.Arrays.asList("authorization", "accept", "user-agent", "content-type");

    private Map<String, String> buildHeaders(RequestOptions options, boolean hasBody) {
        Map<String, String> supplied = new LinkedHashMap<>(config.defaultHeaders());

        if (options != null) {
            supplied.putAll(options.headers());
        }

        Map<String, String> headers = new LinkedHashMap<>();

        for (Map.Entry<String, String> header : supplied.entrySet()) {
            // Dropped rather than overwritten: HTTP header names are
            // case-insensitive and the JDK's builder appends, so a caller's
            // `authorization` would otherwise ride along beside the real
            // credential instead of losing to it.
            if (!RESERVED_HEADERS.contains(
                    header.getKey().toLowerCase(java.util.Locale.ROOT))) {
                headers.put(header.getKey(), header.getValue());
            }
        }

        headers.put("Accept", "application/json");
        headers.put("User-Agent", config.userAgent());

        if (hasBody) {
            headers.put("Content-Type", "application/json");
        }

        return headers;
    }

    private Attempt attempt(
            URI url,
            String method,
            Map<String, String> headers,
            String payload,
            long timeoutMs,
            int attemptNumber) {
        HttpRequest request = buildRequest(url, method, headers, payload, timeoutMs);
        CompletableFuture<HttpResponse<String>> pending = config.httpExchange().sendAsync(request);

        try {
            return Attempt.of(pending.get(timeoutMs, TimeUnit.MILLISECONDS));
        } catch (TimeoutException expired) {
            pending.cancel(true);

            return Attempt.failed(
                    new PactmanTimeoutException(
                            "The request timed out after " + timeoutMs + "ms.",
                            timeoutMs,
                            attemptNumber,
                            expired),
                    false);
        } catch (InterruptedException cancelled) {
            pending.cancel(true);
            // Restore the flag: the caller asked to stop, and code above this
            // frame needs to see that too.
            Thread.currentThread().interrupt();

            return Attempt.failed(
                    new PactmanNetworkException(
                            "The request was cancelled by the caller.", attemptNumber, cancelled),
                    true);
        } catch (ExecutionException failed) {
            Throwable cause = unwrap(failed);

            if (cause instanceof java.net.http.HttpTimeoutException) {
                return Attempt.failed(
                        new PactmanTimeoutException(
                                "The request timed out after " + timeoutMs + "ms.",
                                timeoutMs,
                                attemptNumber,
                                cause),
                        false);
            }

            return Attempt.failed(
                    new PactmanNetworkException(
                            "The request to the Pactman API failed: " + describe(cause),
                            attemptNumber,
                            cause),
                    false);
        }
    }

    private HttpRequest buildRequest(
            URI url, String method, Map<String, String> headers, String payload, long timeoutMs) {
        HttpRequest.Builder request = HttpRequest.newBuilder(url)
                // Belt and braces with the future timeout below: this one tears
                // the exchange down at the socket rather than leaving it running
                // behind a future nobody is waiting on any more.
                .timeout(Duration.ofMillis(timeoutMs));

        for (Map.Entry<String, String> header : headers.entrySet()) {
            try {
                // setHeader, not header: the latter appends, which would send a
                // duplicate whenever a caller spells a header in another case.
                request.setHeader(header.getKey(), header.getValue());
            } catch (IllegalArgumentException restricted) {
                throw new PactmanConfigurationException(
                        "The header \"" + header.getKey()
                                + "\" cannot be set on an outgoing request: "
                                + restricted.getMessage());
            }
        }

        request.setHeader("Authorization", "Bearer " + apiKey);

        if (payload == null) {
            request.method(method, HttpRequest.BodyPublishers.noBody());
        } else {
            request.method(
                    method, HttpRequest.BodyPublishers.ofString(payload, StandardCharsets.UTF_8));
        }

        return request.build();
    }

    /** Spaces requests when {@code maxRequestsPerSecond} is configured. */
    private void throttle() {
        Double limit = config.maxRequestsPerSecond();

        if (limit == null) {
            return;
        }

        long waitMs;

        synchronized (throttleLock) {
            long intervalMs = Math.max(1L, Math.round(1000.0d / limit));
            long now = System.currentTimeMillis();
            long scheduledAt = Math.max(now, nextRequestAtMs);
            nextRequestAtMs = scheduledAt + intervalMs;
            waitMs = scheduledAt - now;
        }

        if (waitMs > 0) {
            sleep(waitMs, 0);
        }
    }

    private void waitBeforeRetry(int attempt, RetryOptions retry, Double retryAfterSeconds) {
        sleep(computeRetryDelay(attempt, retry, retryAfterSeconds, hooks.random()), attempt);
        throwIfCancelled(attempt);
    }

    private void sleep(long millis, int attempt) {
        try {
            hooks.sleep(millis);
        } catch (InterruptedException cancelled) {
            Thread.currentThread().interrupt();

            throw new PactmanNetworkException(
                    "The request was cancelled by the caller.", attempt, cancelled);
        }
    }

    private static void throwIfCancelled(int attempt) {
        if (Thread.currentThread().isInterrupted()) {
            throw new PactmanNetworkException(
                    "The request was cancelled by the caller.", attempt, null);
        }
    }

    /**
     * The delay before the next attempt.
     *
     * <p>A valid {@code Retry-After} wins outright. Otherwise the delay grows
     * exponentially from {@code initialDelayMs}, is capped at {@code maxDelayMs},
     * and — with jitter on — is randomized across the whole range so concurrent
     * clients spread out.
     *
     * @param attempt           the attempt that just failed, counting from one.
     * @param retry             the policy in force.
     * @param retryAfterSeconds the server's {@code Retry-After}, or {@code null}.
     * @param random            a value in {@code [0, 1)} for jitter.
     * @return the delay in milliseconds.
     */
    public static long computeRetryDelay(
            int attempt, RetryOptions retry, Double retryAfterSeconds, double random) {
        if (retry.respectRetryAfter() && retryAfterSeconds != null && retryAfterSeconds >= 0) {
            return Math.round(retryAfterSeconds * 1000.0d);
        }

        double exponential =
                retry.initialDelayMs() * Math.pow(retry.backoffFactor(), attempt - 1.0d);
        double capped = Math.min(exponential, retry.maxDelayMs());

        return Math.round(retry.jitter() ? random * capped : capped);
    }

    /**
     * Reads {@code Retry-After} as either a delay in seconds or an HTTP date.
     *
     * @param raw the header value, or {@code null} when the server sent none.
     * @param now the instant to measure an HTTP date against.
     * @return the delay in seconds, or {@code null} when there is no usable value.
     */
    public static Double readRetryAfter(String raw, Instant now) {
        if (raw == null) {
            return null;
        }

        String trimmed = raw.trim();

        if (trimmed.isEmpty()) {
            return null;
        }

        try {
            double seconds = Double.parseDouble(trimmed);

            // "Infinity" and "1e400" parse, and no wait can honour either.
            if (Double.isFinite(seconds) && seconds >= 0) {
                return seconds;
            }

            return null;
        } catch (NumberFormatException notANumber) {
            // Falls through to the HTTP-date form below.
        }

        try {
            ZonedDateTime when =
                    ZonedDateTime.parse(trimmed, DateTimeFormatter.RFC_1123_DATE_TIME);

            return Math.max(0.0d, (when.toInstant().toEpochMilli() - now.toEpochMilli()) / 1000.0d);
        } catch (DateTimeParseException notADate) {
            return null;
        }
    }

    private static ApiErrorInit buildApiErrorInit(
            int status, Object parsed, String requestId, Double retryAfterSeconds, int attempts) {
        ResponseBody envelope = parsed instanceof Map ? new ResponseBody(asFields(parsed)) : null;
        List<ApiErrorDetail> apiErrors = envelope == null
                ? java.util.Collections.<ApiErrorDetail>emptyList()
                : envelope.getErrors();

        List<String> reasons = new ArrayList<>();

        for (ApiErrorDetail detail : apiErrors) {
            String reason = detail.getReason();

            if (reason != null && !reason.trim().isEmpty()) {
                reasons.add(reason);
            }
        }

        String apiMessage;

        if (!reasons.isEmpty()) {
            apiMessage = String.join("; ", reasons);
        } else if (envelope != null && envelope.getMessage() != null) {
            apiMessage = envelope.getMessage();
        } else if (parsed instanceof String && !((String) parsed).trim().isEmpty()) {
            String text = ((String) parsed).trim();
            apiMessage = text.length() > 500 ? text.substring(0, 500) : text;
        } else {
            apiMessage = null;
        }

        return ApiErrorInit.builder(status)
                .apiMessage(apiMessage)
                .apiCode(envelope == null ? null : envelope.getCode())
                .apiErrors(apiErrors)
                .requestId(requestId)
                .retryAfterSeconds(retryAfterSeconds)
                .raw(parsed)
                .attempts(attempts)
                .build();
    }

    /**
     * Decodes a response body, keeping whatever the server sent when it is not
     * JSON — an unparseable body is still evidence.
     */
    private static Object parseBody(String text) {
        if (text == null || text.trim().isEmpty()) {
            return null;
        }

        try {
            return Json.parse(text);
        } catch (JsonException notJson) {
            return text;
        }
    }

    private static String readRequestId(HttpResponse<String> response) {
        for (String header : new String[] {"x-request-id", "x-correlation-id", "request-id"}) {
            String value = response.headers().firstValue(header).orElse(null);

            if (value != null) {
                return value;
            }
        }

        return null;
    }

    @SuppressWarnings("unchecked")
    private static Map<String, Object> asFields(Object value) {
        return value instanceof Map
                ? (Map<String, Object>) value
                : java.util.Collections.<String, Object>emptyMap();
    }

    private static Throwable unwrap(Throwable error) {
        Throwable cause = error.getCause();

        while (cause instanceof CompletionException && cause.getCause() != null) {
            cause = cause.getCause();
        }

        return cause == null ? error : cause;
    }

    private static String describe(Throwable cause) {
        String message = cause.getMessage();

        return message == null || message.isEmpty() ? cause.getClass().getSimpleName() : message;
    }

    /** One attempt's outcome: a response, or the failure that replaced it. */
    private static final class Attempt {
        private final HttpResponse<String> response;
        private final PactmanException error;
        private final boolean cancelled;

        private Attempt(HttpResponse<String> response, PactmanException error, boolean cancelled) {
            this.response = response;
            this.error = error;
            this.cancelled = cancelled;
        }

        static Attempt of(HttpResponse<String> response) {
            return new Attempt(response, null, false);
        }

        static Attempt failed(PactmanException error, boolean cancelled) {
            return new Attempt(null, error, cancelled);
        }
    }
}
