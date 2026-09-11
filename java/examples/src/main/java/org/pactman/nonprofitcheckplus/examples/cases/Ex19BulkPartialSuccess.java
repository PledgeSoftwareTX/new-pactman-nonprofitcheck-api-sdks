package org.pactman.nonprofitcheckplus.examples.cases;

import java.util.Arrays;
import java.util.List;
import org.pactman.nonprofitcheckplus.devtools.FixtureEins;
import org.pactman.nonprofitcheckplus.examples.support.Example;
import org.pactman.nonprofitcheckplus.examples.support.ExampleContext;
import org.pactman.nonprofitcheckplus.examples.support.ExampleFailedException;
import org.pactman.nonprofitcheckplus.examples.support.Output;
import org.pactman.nonprofitcheckplus.models.ApiErrorDetail;
import org.pactman.nonprofitcheckplus.models.BulkCheckResult;
import org.pactman.nonprofitcheckplus.models.Nonprofit;

/**
 * EX-19 — Partial success in a batch.
 *
 * <p>A batch where some EINs matched is a successful response with the misses
 * listed inside it — not an exception. Code that only looks at the happy path
 * will process the matches and never notice the rest.
 */
public final class Ex19BulkPartialSuccess implements Example {

    @Override
    public String id() {
        return "ex-19";
    }

    @Override
    public String title() {
        return "A 200 that still reports failures";
    }

    @Override
    public void run(String[] args) {
        List<String> eins = Arrays.asList(
                FixtureEins.PUBLIC_CHARITY, FixtureEins.NO_RECORD, FixtureEins.PUBLIC_CHARITY_SECOND);

        try (ExampleContext context = ExampleContext.withFixtures()) {
            BulkCheckResult result = context.client().nonprofits().checkBulk(eins);

            Output.heading("The response");
            Output.field("HTTP status", result.getStatus());
            Output.field("organizations", result.getOrganizations().size());
            Output.field("notFoundEins", result.getNotFoundEins());
            Output.field("errors", result.getErrors().size());
            Output.field("checkCount", result.getCheckCount());

            if (result.getStatus() != 200) {
                throw new ExampleFailedException("Partial success should be an HTTP 200.");
            }

            if (result.getNotFoundEins().isEmpty()) {
                throw new ExampleFailedException("The missing EIN should have been reported.");
            }

            Output.heading("What the errors array carried");

            for (ApiErrorDetail detail : result.getErrors()) {
                Output.field("resource", detail.getResource());
                Output.field("code", detail.getCode());
                Output.field("reason", detail.getReason());
                Output.field("eins", detail.getEins());
            }

            Output.heading("Matched");

            for (Nonprofit organization : result.getOrganizations()) {
                Output.bullet(organization.getEin() + " — " + organization.getOrganizationName());
            }
        }

        Output.note("Three EINs, two records, one 200. getNotFoundEins() is collected from the\n"
                + "envelope's errors array, so the misses are as visible as the matches.\n\n"
                + "Only matched EINs are billed, which is why checkCount rose by two and not by\n"
                + "three — and why usage cannot be reconstructed from the size of the batch you\n"
                + "sent.");
    }
}
