package org.pactman.nonprofitcheckplus.devtools;

import java.util.Collections;
import java.util.List;

/**
 * The result of comparing two signatures.
 *
 * <p>Carries what was excused as well as what failed. A green run that says how
 * much it passed over is honest about its own coverage; one that reports only
 * "no differences" hides the fact that half the paths were unreachable.
 */
public final class Difference {

    private final List<Change> changes;
    private final int nullable;
    private final int unreachable;
    private final int optionalAbsent;

    /**
     * Creates a result.
     *
     * @param changes        the differences that count as drift.
     * @param nullable       paths excused because they differ only over whether
     *                       a value arrived.
     * @param unreachable    paths excused because a container above them arrived
     *                       null or empty.
     * @param optionalAbsent predicted paths excused because nothing promises
     *                       they are present.
     */
    public Difference(List<Change> changes, int nullable, int unreachable, int optionalAbsent) {
        this.changes = Collections.unmodifiableList(changes);
        this.nullable = nullable;
        this.unreachable = unreachable;
        this.optionalAbsent = optionalAbsent;
    }

    /**
     * The differences that count as drift.
     *
     * @return the changes, removals first.
     */
    public List<Change> changes() {
        return changes;
    }

    /**
     * How many differences count as drift.
     *
     * @return the count.
     */
    public int total() {
        return changes.size();
    }

    /**
     * Whether nothing drifted.
     *
     * @return true when there is nothing to report.
     */
    public boolean clean() {
        return changes.isEmpty();
    }

    /**
     * Paths excused because they differ only over whether a value arrived.
     *
     * @return the count.
     */
    public int nullable() {
        return nullable;
    }

    /**
     * Paths excused because a container above them arrived null or empty.
     *
     * @return the count.
     */
    public int unreachable() {
        return unreachable;
    }

    /**
     * Predicted paths excused because nothing promises they are present.
     *
     * @return the count.
     */
    public int optionalAbsent() {
        return optionalAbsent;
    }
}
