/**
 * The SDK version, reported in the User-Agent header.
 *
 * Named `SdkVersion` rather than `Version` because `System.Version` already
 * exists in Apex and would shadow it.
 *
 * The other SDKs pin this against a package manifest with a unit test. Apex
 * cannot read `sfdx-project.json` at runtime, so the equivalent check lives in
 * CI (`scripts/check-version-parity.mjs`) instead.
 */
global class SdkVersion {
    /** The release version, reported in the User-Agent header. */
    global static final String VERSION = '1.0.0';

    /** The package name, reported in the User-Agent header. */
    global static final String PACKAGE_NAME = 'pactman-nonprofit-check-plus';

    /** The value sent as `User-Agent` on every request. */
    global static String userAgent() {
        return PACKAGE_NAME + '/' + VERSION + ' (apex)';
    }
}
