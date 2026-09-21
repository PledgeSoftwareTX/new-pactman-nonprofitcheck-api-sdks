package org.pactman.nonprofitcheckplus.devtools;

import java.io.IOException;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.nio.charset.StandardCharsets;
import java.util.Map;
import org.pactman.nonprofitcheckplus.internal.Json;

/** Reads the contract and any recorded baseline out of the packaged SDK. */
public final class ContractResources {

    /** Where the SDK jar carries its response contract. */
    public static final String CONTRACT_RESOURCE =
            "/org/pactman/nonprofitcheckplus/response-contract.json";

    /** The committed recording of production that {@code smoke-live} is held against. */
    public static final String BASELINE_RESOURCE =
            "/org/pactman/nonprofitcheckplus/devtools/response-baseline.json";

    /**
     * Where {@link #BASELINE_RESOURCE} lives in the source tree, relative to the
     * {@code java/} directory, so {@code baseline-record} rewrites the committed file.
     */
    public static final String BASELINE_SOURCE =
            "devtools/src/main/resources" + BASELINE_RESOURCE;

    private ContractResources() {
    }

    /**
     * The response contract this package promises.
     *
     * <p>Read from the SDK's own resources rather than from a path on disk, so
     * what is checked is what the published artifact carries.
     *
     * @return the parsed contract.
     */
    @SuppressWarnings("unchecked")
    public static Map<String, Object> contract() {
        return (Map<String, Object>) Json.parse(read(CONTRACT_RESOURCE));
    }

    /**
     * Reads a classpath resource as text.
     *
     * @param resource the absolute resource path.
     * @return the contents.
     */
    /**
     * The committed baseline.
     *
     * @return the parsed recording.
     */
    @SuppressWarnings("unchecked")
    public static Map<String, Object> baseline() {
        return (Map<String, Object>) Json.parse(read(BASELINE_RESOURCE));
    }

    public static String read(String resource) {
        try (InputStream stream = ContractResources.class.getResourceAsStream(resource)) {
            if (stream == null) {
                throw new IllegalStateException("No such resource: " + resource);
            }

            StringBuilder text = new StringBuilder();
            char[] buffer = new char[8192];

            try (InputStreamReader reader = new InputStreamReader(stream, StandardCharsets.UTF_8)) {
                int read;

                while ((read = reader.read(buffer)) != -1) {
                    text.append(buffer, 0, read);
                }
            }

            return text.toString();
        } catch (IOException unreadable) {
            throw new IllegalStateException(resource + " is not readable", unreadable);
        }
    }
}
