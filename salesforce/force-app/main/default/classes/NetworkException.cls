/**
 * The request produced no HTTP response.
 *
 * In Apex this most often means the endpoint is not reachable, the Named
 * Credential is misconfigured, or the org has no callout permission for the
 * host — not a transient network blip.
 */
global class NetworkException extends PactmanException {
    /** How many attempts were made before this exception was surfaced. */
    global Integer attempts { get; private set; }

    /** Package-internal. */
    public NetworkException initNetwork(Integer attempts) {
        this.attempts = attempts == null ? 1 : attempts;
        return this;
    }
}
