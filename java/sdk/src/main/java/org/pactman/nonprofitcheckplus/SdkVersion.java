package org.pactman.nonprofitcheckplus;

import java.util.Locale;

/**
 * The SDK version, reported in the {@code User-Agent} header.
 *
 * <p>Held as a compile-time constant rather than read from the jar manifest at
 * runtime: a manifest lookup returns nothing once the SDK is shaded into a fat
 * jar, which is exactly the deployment where knowing the version matters. A unit
 * test holds this against the POM so the two cannot drift.
 */
public final class SdkVersion {

    /** The released version of this package. */
    public static final String VERSION = "1.0.0";

    /** The distribution name, reported in the {@code User-Agent} header. */
    public static final String PACKAGE_NAME = "pactman-nonprofit-check-plus";

    private SdkVersion() {
    }

    /**
     * The {@code User-Agent} this SDK sends.
     *
     * <p>Formatted as
     * {@code pactman-nonprofit-check-plus/<version> (java/<version>; <os>)}, so
     * a server-side log can tell which SDK and which runtime made a call.
     *
     * @return the user agent string.
     */
    public static String userAgent() {
        String java = System.getProperty("java.version", "unknown");
        String os = System.getProperty("os.name", "unknown");

        return String.format(
                Locale.ROOT, "%s/%s (java/%s; %s)", PACKAGE_NAME, VERSION, java, os);
    }
}
