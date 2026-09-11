package org.pactman.nonprofitcheckplus.config;

import java.net.URI;
import java.net.URISyntaxException;
import org.pactman.nonprofitcheckplus.PactmanEnvironment;
import org.pactman.nonprofitcheckplus.SdkVersion;
import org.pactman.nonprofitcheckplus.exceptions.PactmanConfigurationException;
import org.pactman.nonprofitcheckplus.http.HttpExchange;
import org.pactman.nonprofitcheckplus.http.JdkHttpExchange;

/**
 * Validates and resolves constructor options.
 *
 * <p>Every rejection happens here, at construction, rather than on the first
 * request: a client that cannot work should say so where it is built, not
 * halfway through a batch.
 */
public final class ConfigResolver {

    private ConfigResolver() {
    }

    /**
     * Validates options and fills in every default.
     *
     * @param options the caller's options.
     * @return the API key and the resolved configuration, held apart.
     * @throws PactmanConfigurationException for a missing or blank API key, an
     *         unknown environment, a malformed base URL, or a nonsensical
     *         numeric option.
     */
    public static Resolved resolve(PactmanClientOptions options) {
        if (options == null) {
            throw new PactmanConfigurationException(
                    "PactmanClient requires options containing an apiKey.");
        }

        String apiKey = validateApiKey(options.apiKey());
        String baseUrl = resolveBaseUrl(options);
        long timeoutMs = resolveTimeout(options.timeoutMs());
        Double maxRequestsPerSecond = resolveRequestsPerSecond(options.maxRequestsPerSecond());

        ClientConfig config = new ClientConfig(
                baseUrl,
                options.baseUrl() == null ? environmentOrDefault(options.environment()) : null,
                timeoutMs,
                options.retry() == null ? RetryOptions.defaults() : options.retry(),
                maxRequestsPerSecond,
                options.defaultHeaders(),
                SdkVersion.userAgent(),
                resolveExchange(options));

        return new Resolved(apiKey, config);
    }

    private static PactmanEnvironment environmentOrDefault(PactmanEnvironment environment) {
        return environment == null ? PactmanEnvironment.PRODUCTION : environment;
    }

    private static String validateApiKey(String apiKey) {
        if (apiKey == null) {
            throw new PactmanConfigurationException(
                    "A Pactman API key is required. Pass `apiKey`, for example from "
                            + "System.getenv(\"PACTMAN_API_KEY\").");
        }

        if (apiKey.trim().isEmpty()) {
            throw new PactmanConfigurationException(
                    "The Pactman API key is empty. Check that the environment variable holding "
                            + "it is set.");
        }

        return apiKey.trim();
    }

    private static String resolveBaseUrl(PactmanClientOptions options) {
        if (options.baseUrl() != null) {
            return validateBaseUrl(options.baseUrl());
        }

        return environmentOrDefault(options.environment()).baseUrl();
    }

    private static String validateBaseUrl(String baseUrl) {
        if (baseUrl.trim().isEmpty()) {
            throw new PactmanConfigurationException("`baseUrl` must be a non-empty URL string.");
        }

        URI parsed;

        try {
            parsed = new URI(baseUrl.trim());
        } catch (URISyntaxException malformed) {
            throw new PactmanConfigurationException(
                    "`baseUrl` is not a valid URL: \"" + baseUrl
                            + "\". Expected something like https://entities.pactman.org.");
        }

        String scheme = parsed.getScheme() == null
                ? null
                : parsed.getScheme().toLowerCase(java.util.Locale.ROOT);

        if (!"https".equals(scheme) && !"http".equals(scheme)) {
            throw new PactmanConfigurationException(
                    "`baseUrl` must use http or https, received \"" + parsed.getScheme() + "\".");
        }

        if (parsed.getHost() == null) {
            throw new PactmanConfigurationException(
                    "`baseUrl` is missing a host: \"" + baseUrl + "\".");
        }

        String path = parsed.getRawPath() == null ? "" : parsed.getRawPath();

        while (path.endsWith("/")) {
            path = path.substring(0, path.length() - 1);
        }

        return scheme + "://" + parsed.getRawAuthority() + path;
    }

    private static long resolveTimeout(Long timeoutMs) {
        if (timeoutMs == null) {
            return PactmanClientOptions.DEFAULT_TIMEOUT_MS;
        }

        if (timeoutMs <= 0) {
            throw new PactmanConfigurationException(
                    "`timeoutMs` must be greater than zero. There is no way to disable the "
                            + "timeout.");
        }

        return timeoutMs;
    }

    private static Double resolveRequestsPerSecond(Double value) {
        if (value == null) {
            return null;
        }

        if (value.isNaN() || value.isInfinite() || value <= 0) {
            throw new PactmanConfigurationException(
                    "`maxRequestsPerSecond` must be a finite number greater than zero, or "
                            + "omitted.");
        }

        return value;
    }

    private static HttpExchange resolveExchange(PactmanClientOptions options) {
        if (options.httpExchange() != null) {
            return options.httpExchange();
        }

        if (options.httpClient() != null) {
            return new JdkHttpExchange(options.httpClient());
        }

        return JdkHttpExchange.withDefaults();
    }

    /** The API key and the resolved configuration, held apart on purpose. */
    public static final class Resolved {
        private final String apiKey;
        private final ClientConfig config;

        private Resolved(String apiKey, ClientConfig config) {
            this.apiKey = apiKey;
            this.config = config;
        }

        /**
         * The validated API key.
         *
         * @return the key, trimmed.
         */
        public String apiKey() {
            return apiKey;
        }

        /**
         * The resolved configuration, which does not carry the key.
         *
         * @return the configuration.
         */
        public ClientConfig config() {
            return config;
        }
    }
}
