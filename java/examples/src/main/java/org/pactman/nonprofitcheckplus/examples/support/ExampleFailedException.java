package org.pactman.nonprofitcheckplus.examples.support;

/**
 * An example ran but did not get the outcome it was demonstrating.
 *
 * <p>Examples run in-process under {@code --smoke}, so one that has failed says
 * so by throwing rather than by exiting the process out from under everything
 * after it.
 */
public final class ExampleFailedException extends RuntimeException {

    private static final long serialVersionUID = 1L;

    /**
     * Creates the exception.
     *
     * @param message what the example expected, and what it saw instead.
     */
    public ExampleFailedException(String message) {
        super(message);
    }
}
