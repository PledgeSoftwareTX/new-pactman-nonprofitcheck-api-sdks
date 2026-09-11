package org.pactman.nonprofitcheckplus;

import java.util.Collections;
import java.util.List;
import java.util.stream.Collectors;

/**
 * A named Pactman environment.
 *
 * <p>Endpoint hosts are declared here and nowhere else. Nothing in this package
 * should contain a literal Pactman host.
 *
 * <p>Pactman's QA, SIT and sandbox hosts are internal and are deliberately not
 * exposed. Point at one with
 * {@link org.pactman.nonprofitcheckplus.config.PactmanClientOptions.Builder#baseUrl(String)}
 * if you have been given access to it.
 */
public enum PactmanEnvironment {

    /** The Pactman production API. */
    PRODUCTION("production", "https://entities.pactman.org");

    private final String environmentName;
    private final String baseUrl;

    PactmanEnvironment(String environmentName, String baseUrl) {
        this.environmentName = environmentName;
        this.baseUrl = baseUrl;
    }

    /**
     * The environment's name as the SDKs in every language spell it.
     *
     * @return the lowercase name, such as {@code production}.
     */
    public String environmentName() {
        return environmentName;
    }

    /**
     * The base URL requests to this environment are sent to.
     *
     * @return an absolute origin, with no trailing slash.
     */
    public String baseUrl() {
        return baseUrl;
    }

    /**
     * Looks an environment up by name, case-insensitively.
     *
     * @param name the environment name, such as {@code production}.
     * @return the environment, or {@code null} when no environment has that name.
     */
    public static PactmanEnvironment fromName(String name) {
        if (name == null) {
            return null;
        }

        String needle = name.trim().toLowerCase(java.util.Locale.ROOT);

        for (PactmanEnvironment environment : values()) {
            if (environment.environmentName.equals(needle)) {
                return environment;
            }
        }

        return null;
    }

    /**
     * Every environment name the SDK understands.
     *
     * @return the supported names, in declaration order.
     */
    public static List<String> supportedNames() {
        return Collections.unmodifiableList(
                java.util.Arrays.stream(values())
                        .map(PactmanEnvironment::environmentName)
                        .collect(Collectors.toList()));
    }

    @Override
    public String toString() {
        return environmentName;
    }
}
