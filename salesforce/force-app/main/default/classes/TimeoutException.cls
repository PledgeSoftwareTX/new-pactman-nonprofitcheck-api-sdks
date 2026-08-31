/**
 * The callout exceeded the configured timeout.
 *
 * Salesforce also caps the *cumulative* callout time in one transaction at 120
 * seconds across all callouts, so a run of slow requests can trip this even
 * when each individual timeout is generous.
 */
global class TimeoutException extends PactmanException {
    /** The timeout that was exceeded, in milliseconds. */
    global Integer timeoutMs { get; private set; }

    /** How many attempts were made before this exception was surfaced. */
    global Integer attempts { get; private set; }

    /** Package-internal. */
    public TimeoutException initTimeout(Integer timeoutMs, Integer attempts) {
        this.timeoutMs = timeoutMs;
        this.attempts = attempts == null ? 1 : attempts;
        return this;
    }
}
