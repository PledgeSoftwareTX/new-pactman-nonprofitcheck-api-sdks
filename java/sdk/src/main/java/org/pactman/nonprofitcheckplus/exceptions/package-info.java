/**
 * The error taxonomy.
 *
 * <p>Every exception this SDK throws is a
 * {@link org.pactman.nonprofitcheckplus.exceptions.PactmanException} carrying a
 * stable {@link org.pactman.nonprofitcheckplus.exceptions.ErrorCategory} and an
 * {@link org.pactman.nonprofitcheckplus.exceptions.ErrorOrigin}, so callers can
 * branch on exception type or on category without parsing message strings.
 *
 * <p>API keys are never placed into an exception message, an exception
 * property, or any {@code toMap()} output.
 */
package org.pactman.nonprofitcheckplus.exceptions;
