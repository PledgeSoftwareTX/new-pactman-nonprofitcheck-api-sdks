package org.pactman.nonprofitcheckplus.examples.support;

/** One runnable example. */
public interface Example {

    /**
     * The example's identifier, such as {@code ex-01}.
     *
     * @return the id.
     */
    String id();

    /**
     * A one-line title, shown by {@code --list}.
     *
     * @return the title.
     */
    String title();

    /**
     * Runs the example.
     *
     * @param args arguments after the example id, such as an EIN to look up.
     * @throws Exception when the example cannot complete.
     */
    void run(String[] args) throws Exception;
}
