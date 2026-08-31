/**
 * Base class for every exception this SDK throws.
 *
 * Catch this to catch everything the SDK can raise. Every subclass carries a
 * stable {@link ErrorCategory} and an {@link ErrorOrigin}, so callers branch on
 * the exception type or on the category — never on message text.
 *
 * The API key is never placed into an exception message or property. It is not
 * reachable from Apex at all: it lives in the External Credential behind the
 * Named Credential, and the platform injects it at callout time.
 *
 * Apex exception classes do not take custom constructors reliably, so these are
 * built through {@link Errors} and populated with the package-internal `init`
 * methods below. Subscribers construct none of them.
 */
global class PactmanException extends Exception {
    /** The stable category for this failure. */
    global ErrorCategory category { get; private set; }

    /** Whether the SDK raised this locally or derived it from a response. */
    global ErrorOrigin origin { get; private set; }

    /** Package-internal. Not `global`, so subscribers cannot reach it. */
    public PactmanException init(ErrorCategory category, ErrorOrigin origin) {
        this.category = category;
        this.origin = origin;
        return this;
    }
}
