package org.pactman.nonprofitcheckplus.devtools;

import com.sun.net.httpserver.HttpExchange;
import com.sun.net.httpserver.HttpServer;
import java.io.IOException;
import java.io.InputStream;
import java.net.InetSocketAddress;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.ThreadLocalRandom;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import org.pactman.nonprofitcheckplus.Endpoints;
import org.pactman.nonprofitcheckplus.internal.Json;

/**
 * A stand-in for the Nonprofit Check Plus API, so the examples can be run in CI
 * without a real key or network access.
 *
 * <p>Only the two check endpoints are implemented, with the same envelope shape,
 * auth header, batch limit, bulk matching semantics and cumulative check count
 * as the real service. Records come from {@link Fixtures}.
 */
public final class FixtureApi implements AutoCloseable {

    private static final Pattern SINGLE_PATH =
            Pattern.compile("^/api/entities/nonprofitcheck/v1/us/ein/(\\d{9})$");

    /** How long the slow control EIN holds a response open. */
    private static final long SLOW_RESPONSE_MS = 5_000L;

    /** How many times the transient-failure control EIN fails before succeeding. */
    private static final int TRANSIENT_FAILURES = 2;

    private final HttpServer server;
    private final ExecutorService workers;
    private final String apiKey;
    private final String baseUrl;

    /** A running total for the billing cycle, not the size of the current request. */
    private final AtomicInteger checksUsedThisCycle = new AtomicInteger();

    private final AtomicInteger transientFailuresLeft = new AtomicInteger(TRANSIENT_FAILURES);

    private FixtureApi(HttpServer server, ExecutorService workers, String apiKey) {
        this.server = server;
        this.workers = workers;
        this.apiKey = apiKey;
        this.baseUrl = "http://127.0.0.1:" + server.getAddress().getPort();
    }

    /**
     * Starts the fixture API on a free port.
     *
     * @param apiKey the key the server accepts.
     * @return the running server.
     * @throws IOException when the port cannot be bound.
     */
    public static FixtureApi start(String apiKey) throws IOException {
        HttpServer server = HttpServer.create(new InetSocketAddress("127.0.0.1", 0), 0);
        ExecutorService workers = Executors.newCachedThreadPool(runnable -> {
            Thread thread = new Thread(runnable, "pactman-fixture-api");
            thread.setDaemon(true);

            return thread;
        });

        FixtureApi api = new FixtureApi(server, workers, apiKey);

        server.createContext("/", api::handle);
        server.setExecutor(workers);
        server.start();

        return api;
    }

    /**
     * The URL to point a client at.
     *
     * @return the base URL.
     */
    public String baseUrl() {
        return baseUrl;
    }

    /**
     * The key this server accepts.
     *
     * @return the API key.
     */
    public String apiKey() {
        return apiKey;
    }

    @Override
    public void close() {
        server.stop(0);
        // HttpServer.stop does not touch an executor the caller supplied, so
        // without this the pool's threads outlive the server — including any
        // still parked in the slow-response handler. shutdownNow interrupts
        // them, which is what that handler is written to expect.
        workers.shutdownNow();
    }

    private void handle(HttpExchange exchange) throws IOException {
        try {
            String path = exchange.getRequestURI().getPath();
            String authorization = exchange.getRequestHeaders().getFirst("Authorization");

            if (!("Bearer " + apiKey).equals(authorization)) {
                send(exchange, 401, errorEnvelope(401, "Unauthorized",
                        detail("nonprofitcheck", "The API key was rejected", 401, null)),
                        Collections.<String, String>emptyMap());
                return;
            }

            Matcher single = SINGLE_PATH.matcher(path);

            if ("GET".equals(exchange.getRequestMethod()) && single.matches()) {
                handleSingle(exchange, single.group(1));
                return;
            }

            if ("POST".equals(exchange.getRequestMethod())
                    && Endpoints.BULK_CHECK_PATH.equals(path)) {
                handleBulk(exchange);
                return;
            }

            send(exchange, 404, errorEnvelope(404, "Not Found",
                    detail("gateway", "No such endpoint: " + path, 404, null)),
                    Collections.<String, String>emptyMap());
        } finally {
            exchange.close();
        }
    }

    private void handleSingle(HttpExchange exchange, String ein) throws IOException {
        if (FixtureEins.CONTROL_RATE_LIMITED.equals(ein)) {
            send(exchange, 429, errorEnvelope(429, "Too Many Requests",
                    detail("nonprofitcheck", "Rate limit exceeded", 429, null)),
                    Collections.singletonMap("Retry-After", "1"));
            return;
        }

        if (FixtureEins.CONTROL_TRANSIENT_FAILURE.equals(ein)) {
            if (transientFailuresLeft.getAndDecrement() > 0) {
                send(exchange, 503, errorEnvelope(503, "Service Unavailable",
                        detail("nonprofitcheck", "Upstream temporarily unavailable", 503, null)),
                        Collections.<String, String>emptyMap());
                return;
            }

            // Reset, so a second example demonstrating retries sees the same
            // sequence rather than an already-exhausted server.
            transientFailuresLeft.set(TRANSIENT_FAILURES);
            send(exchange, 200,
                    envelope(Fixtures.organization(FixtureEins.PUBLIC_CHARITY), null,
                            checksUsedThisCycle.incrementAndGet()),
                    Collections.<String, String>emptyMap());
            return;
        }

        if (FixtureEins.CONTROL_SLOW.equals(ein)) {
            try {
                Thread.sleep(SLOW_RESPONSE_MS);
            } catch (InterruptedException interrupted) {
                Thread.currentThread().interrupt();
                return;
            }
        }

        if (!Fixtures.has(ein)) {
            send(exchange, 404, errorEnvelope(404, "Not Found",
                    detail("nonprofitcheck",
                            "There are no matching nonprofits in our records for this EIN",
                            404,
                            Collections.singletonList(ein))),
                    Collections.<String, String>emptyMap());
            return;
        }

        send(exchange, 200,
                envelope(Fixtures.organization(ein), null, checksUsedThisCycle.incrementAndGet()),
                Collections.<String, String>emptyMap());
    }

    private void handleBulk(HttpExchange exchange) throws IOException {
        Object body = readBody(exchange);

        if (!(body instanceof List)) {
            send(exchange, 400, errorEnvelope(400, "Bad Request",
                    detail("nonprofitcheckbulk", "Expected a JSON array of EINs", 400, null)),
                    Collections.<String, String>emptyMap());
            return;
        }

        List<?> requested = (List<?>) body;

        if (requested.isEmpty() || requested.size() > Endpoints.MAX_BULK_EINS) {
            send(exchange, 400, errorEnvelope(400, "Bad Request",
                    detail("nonprofitcheckbulk",
                            "Between 1 and " + Endpoints.MAX_BULK_EINS + " EINs are required",
                            400,
                            null)),
                    Collections.<String, String>emptyMap());
            return;
        }

        // The API matches by set membership: a repeated EIN comes back once, and
        // the response is not ordered to follow the request.
        Set<String> unique = new LinkedHashSet<>();

        for (Object entry : requested) {
            if (entry instanceof String) {
                unique.add((String) entry);
            }
        }

        List<Object> found = new ArrayList<>();
        List<String> missing = new ArrayList<>();

        for (String ein : unique) {
            if (Fixtures.has(ein)) {
                found.add(Fixtures.organization(ein));
            } else {
                missing.add(ein);
            }
        }

        if (found.isEmpty()) {
            send(exchange, 404, errorEnvelope(404, "Not Found",
                    detail("nonprofitcheckbulk",
                            "There are no matching nonprofits in our records for this set of EINs",
                            404,
                            missing)),
                    Collections.<String, String>emptyMap());
            return;
        }

        // Only matched EINs are billed, which is why a caller cannot reconstruct
        // usage from the size of the batch it sent.
        int used = checksUsedThisCycle.addAndGet(found.size());
        List<Object> errors = missing.isEmpty()
                ? null
                : Collections.<Object>singletonList(detail(
                        "nonprofitcheckbulk",
                        "There are no matching nonprofits in our records for this set of EINs",
                        404,
                        missing));

        send(exchange, 200, envelope(found, errors, used), Collections.<String, String>emptyMap());
    }

    private static Map<String, Object> detail(
            String resource, String reason, int code, List<String> eins) {
        Map<String, Object> detail = new LinkedHashMap<>();
        detail.put("resource", resource);
        detail.put("reason", reason);
        detail.put("code", (long) code);

        if (eins != null) {
            detail.put("eins", eins);
        }

        return detail;
    }

    private static Map<String, Object> envelope(Object data, Object errors, int checkCount) {
        Map<String, Object> envelope = new LinkedHashMap<>();
        envelope.put("code", 200L);
        envelope.put("message", "OK");
        envelope.put("errors", errors);
        envelope.put("data", data);
        envelope.put("timeTaken", 2L + ThreadLocalRandom.current().nextInt(40));
        envelope.put("nonprofit_check_count", (long) checkCount);

        return envelope;
    }

    private static Map<String, Object> errorEnvelope(
            int code, String message, Map<String, Object> detail) {
        Map<String, Object> envelope = new LinkedHashMap<>();
        envelope.put("code", (long) code);
        envelope.put("message", message);
        envelope.put("errors", new ArrayList<>(Arrays.asList(detail)));
        envelope.put("data", null);
        envelope.put("timeTaken", 1L);
        envelope.put("nonprofit_check_count", 0L);

        return envelope;
    }

    private static Object readBody(HttpExchange exchange) throws IOException {
        try (InputStream stream = exchange.getRequestBody()) {
            java.io.ByteArrayOutputStream buffer = new java.io.ByteArrayOutputStream();
            byte[] chunk = new byte[8192];
            int read;

            while ((read = stream.read(chunk)) != -1) {
                buffer.write(chunk, 0, read);
            }

            String text = new String(buffer.toByteArray(), StandardCharsets.UTF_8);

            return text.trim().isEmpty() ? null : Json.parse(text);
        }
    }

    private static void send(
            HttpExchange exchange, int status, Map<String, Object> body, Map<String, String> headers)
            throws IOException {
        byte[] payload = Json.write(body).getBytes(StandardCharsets.UTF_8);

        exchange.getResponseHeaders().set("Content-Type", "application/json");
        exchange.getResponseHeaders().set(
                "X-Request-Id",
                "fixture-" + Long.toHexString(ThreadLocalRandom.current().nextLong()));

        for (Map.Entry<String, String> header : headers.entrySet()) {
            exchange.getResponseHeaders().set(header.getKey(), header.getValue());
        }

        exchange.sendResponseHeaders(status, payload.length);
        exchange.getResponseBody().write(payload);
    }
}
