package org.pactman.nonprofitcheckplus.examples.cases;

import java.util.Arrays;
import java.util.List;
import org.pactman.nonprofitcheckplus.Endpoints;
import org.pactman.nonprofitcheckplus.Sources;
import org.pactman.nonprofitcheckplus.devtools.FixtureEins;
import org.pactman.nonprofitcheckplus.examples.support.Example;
import org.pactman.nonprofitcheckplus.examples.support.ExampleContext;
import org.pactman.nonprofitcheckplus.examples.support.ExampleFailedException;
import org.pactman.nonprofitcheckplus.exceptions.PactmanValidationException;
import org.pactman.nonprofitcheckplus.exceptions.ValidationIssue;
import org.pactman.nonprofitcheckplus.models.BulkCheckResult;
import org.pactman.nonprofitcheckplus.models.Nonprofit;
import org.pactman.nonprofitcheckplus.models.Pub78Source;

/**
 * Bulk nonprofit check with local validation and result iteration.
 *
 * <p>The key is read from the environment. Never hard-code it, and never run
 * this inside an artifact that ships to a user — the key is a private
 * server-side credential.
 */
public final class Bulk implements Example {

    @Override
    public String id() {
        return "bulk";
    }

    @Override
    public String title() {
        return "Bulk check with local validation and result iteration";
    }

    @Override
    public void run(String[] args) {
        List<String> eins = Arrays.asList("41-1787097", FixtureEins.PUBLIC_CHARITY_SECOND);

        System.out.println("Checking " + eins.size() + " EINs (server limit is "
                + Endpoints.MAX_BULK_EINS + " per request).");

        try (ExampleContext context = ExampleContext.withFixtures()) {
            BulkCheckResult result = context.client().nonprofits().checkBulk(eins);

            System.out.println();
            System.out.println("Matched " + result.getOrganizations().size() + " organizations.");

            for (Nonprofit organization : result.getOrganizations()) {
                Pub78Source pub78 = Sources.pub78(organization);

                System.out.println("  " + organization.getEin() + "  "
                        + organization.getOrganizationName() + "  pub78_listed="
                        + (pub78 == null ? "n/a" : pub78.getVerified()));
            }

            // EINs with no record come back on a successful response, not as an error.
            if (!result.getNotFoundEins().isEmpty()) {
                System.out.println();
                System.out.println("No record for: " + String.join(", ", result.getNotFoundEins()));
            }

            System.out.println();
            System.out.println("Checks consumed: " + result.getCheckCount());
        } catch (PactmanValidationException failure) {
            // Nothing was sent — the whole batch is rejected before the request.
            System.err.println("Local validation failed, no request was sent:");

            for (ValidationIssue issue : failure.issues()) {
                System.err.println("  index " + issue.index() + ": " + issue.message());
            }

            throw new ExampleFailedException("The batch should have passed local validation.");
        }

        // Duplicates are sent as supplied, because each one consumes quota. Pass
        // BulkRequestOptions with dedupe(true) to collapse them first.
    }
}
