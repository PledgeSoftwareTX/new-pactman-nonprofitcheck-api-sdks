package org.pactman.nonprofitcheckplus.http;

import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.util.concurrent.CompletableFuture;

/**
 * The default {@link HttpExchange}, backed by the JDK's own HTTP client.
 *
 * <p>Nothing here interprets the response. Status handling, retries and
 * timeouts belong to {@link Transport}; this class only sends.
 */
public final class JdkHttpExchange implements HttpExchange {

    private final HttpClient client;

    /**
     * Wraps an {@link HttpClient}.
     *
     * @param client the client to send through.
     */
    public JdkHttpExchange(HttpClient client) {
        this.client = client;
    }

    /**
     * Builds an exchange over a client with sensible connection settings.
     *
     * @return an exchange over a newly built client.
     */
    public static JdkHttpExchange withDefaults() {
        return new JdkHttpExchange(
                HttpClient.newBuilder()
                        .connectTimeout(java.time.Duration.ofSeconds(10))
                        .followRedirects(HttpClient.Redirect.NORMAL)
                        .build());
    }

    @Override
    public CompletableFuture<HttpResponse<String>> sendAsync(HttpRequest request) {
        return client.sendAsync(
                request, HttpResponse.BodyHandlers.ofString(java.nio.charset.StandardCharsets.UTF_8));
    }
}
