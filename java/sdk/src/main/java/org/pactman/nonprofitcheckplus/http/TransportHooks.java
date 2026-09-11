package org.pactman.nonprofitcheckplus.http;

/**
 * The two pieces of real-world nondeterminism the transport depends on.
 *
 * <p>Substituted by the test suite so retry and throttle tests assert on the
 * delays that <em>would</em> have been waited rather than waiting them. Not part
 * of the supported API surface; it is not covered by semantic versioning.
 */
public interface TransportHooks {

    /** Hooks backed by the real clock and a real random source. */
    TransportHooks DEFAULT = new TransportHooks() {
        @Override
        public void sleep(long millis) throws InterruptedException {
            if (millis > 0) {
                Thread.sleep(millis);
            }
        }

        @Override
        public double random() {
            return java.util.concurrent.ThreadLocalRandom.current().nextDouble();
        }
    };

    /**
     * Waits before the next attempt.
     *
     * @param millis how long to wait.
     * @throws InterruptedException if the waiting thread is interrupted, which
     *         is how a caller cancels a call that is between attempts.
     */
    void sleep(long millis) throws InterruptedException;

    /**
     * A value in {@code [0, 1)}, used for backoff jitter.
     *
     * @return the random value.
     */
    double random();
}
