/**
 * The HTTP layer.
 *
 * <p>{@link org.pactman.nonprofitcheckplus.http.Transport} owns authentication,
 * timeouts, retries and rate limiting;
 * {@link org.pactman.nonprofitcheckplus.http.HttpExchange} is the single call it
 * makes, so an application can substitute its own client without this package
 * growing an option for every reason someone might want to.
 */
package org.pactman.nonprofitcheckplus.http;
