package org.pactman.nonprofitcheckplus.http;

import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.util.concurrent.CompletableFuture;

/**
 * The one HTTP call this SDK depends on.
 *
 * <p>The seam exists for the same reason the Node SDK accepts a {@code fetch}:
 * so a test can answer a request without a socket, and so an application can
 * put its own instrumentation, proxy or connection pool in front of the SDK
 * without this package growing options for each of them.
 *
 * <p>Timeouts, retries, backoff and rate limiting live in
 * {@link Transport}, above this interface. An implementation is responsible for
 * one exchange and nothing more.
 */
@FunctionalInterface
public interface HttpExchange {

    /**
     * Sends one request.
     *
     * @param request the request, with headers and body already set.
     * @return a future completing with the response, or completing
     *         exceptionally when the exchange fails.
     */
    CompletableFuture<HttpResponse<String>> sendAsync(HttpRequest request);
}
