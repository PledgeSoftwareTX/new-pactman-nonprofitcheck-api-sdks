/**
 * The Pactman Nonprofit Check Plus SDK for Java.
 *
 * <p>Server-side only — the API key is a private credential.
 *
 * <pre>{@code
 * try (PactmanClient client = new PactmanClient(System.getenv("PACTMAN_API_KEY"))) {
 *     SingleCheckResult result = client.nonprofits().check("41-1787097");
 *     System.out.println(result.getNonprofit().getOrganizationName());
 * }
 * }</pre>
 *
 * <p>Start at {@link org.pactman.nonprofitcheckplus.PactmanClient}. Response
 * models are in {@link org.pactman.nonprofitcheckplus.models}, the failure
 * taxonomy in {@link org.pactman.nonprofitcheckplus.exceptions}, and everything
 * configurable in {@link org.pactman.nonprofitcheckplus.config}.
 */
package org.pactman.nonprofitcheckplus;
