package org.pactman.nonprofitcheckplus.support;

import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import org.pactman.nonprofitcheckplus.http.TransportHooks;

/**
 * Records the delays the transport asked for instead of waiting them, so retry
 * and throttle tests assert on the backoff schedule and still run instantly.
 */
public final class RecordingHooks implements TransportHooks {

    private final List<Long> delays = Collections.synchronizedList(new ArrayList<Long>());
    private final double random;

    /**
     * Records delays, reporting a fixed value for jitter.
     *
     * @param random the value to return from {@link #random()}. Use 1.0 to make
     *               full jitter produce the whole computed delay, which is what
     *               makes the backoff schedule assertable.
     */
    public RecordingHooks(double random) {
        this.random = random;
    }

    /** Records delays with jitter at its maximum, so backoff is deterministic. */
    public RecordingHooks() {
        this(1.0d);
    }

    /**
     * Every delay the transport asked for, in order.
     *
     * @return the delays in milliseconds.
     */
    public List<Long> delays() {
        return delays;
    }

    @Override
    public void sleep(long millis) throws InterruptedException {
        if (Thread.currentThread().isInterrupted()) {
            throw new InterruptedException("interrupted while sleeping");
        }

        delays.add(millis);
    }

    @Override
    public double random() {
        return random;
    }
}
