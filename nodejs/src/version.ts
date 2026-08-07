/**
 * The SDK version, reported in the User-Agent header.
 *
 * Kept in sync with `package.json` by a unit test rather than a build step so
 * that the value is available in both ESM and CJS output without a JSON import.
 */
export const VERSION = '1.0.2';

/** The npm package name, reported in the User-Agent header. */
export const PACKAGE_NAME = '@pactmandev/nonprofit-check-plus';
