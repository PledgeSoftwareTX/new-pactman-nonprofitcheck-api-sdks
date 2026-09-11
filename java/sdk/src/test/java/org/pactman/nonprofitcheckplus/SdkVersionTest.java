package org.pactman.nonprofitcheckplus;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.io.IOException;
import java.io.InputStream;
import java.util.Properties;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

/**
 * Holds the compile-time version constant against the POM.
 *
 * <p>The constant exists because a manifest lookup returns nothing once the SDK
 * is shaded into a fat jar. This test is what keeps that duplication honest, in
 * place of a build step rewriting the source.
 */
class SdkVersionTest {

    @Test
    @DisplayName("the version constant matches the POM")
    void versionMatchesPom() throws IOException {
        Properties build = new Properties();

        try (InputStream stream =
                getClass().getResourceAsStream("/version.properties")) {
            build.load(stream);
        }

        assertEquals(build.getProperty("version"), SdkVersion.VERSION);
    }

    @Test
    @DisplayName("the user agent names the package, the version and the runtime")
    void userAgentIdentifiesTheSdk() {
        String userAgent = SdkVersion.userAgent();

        assertTrue(userAgent.startsWith(SdkVersion.PACKAGE_NAME + "/" + SdkVersion.VERSION));
        assertTrue(userAgent.contains("java/"));
    }
}
