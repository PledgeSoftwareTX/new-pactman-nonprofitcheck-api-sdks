package org.pactman.nonprofitcheckplus.examples.cases;

import java.util.Arrays;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import org.pactman.nonprofitcheckplus.devtools.FixtureEins;
import org.pactman.nonprofitcheckplus.examples.support.Example;
import org.pactman.nonprofitcheckplus.examples.support.ExampleContext;
import org.pactman.nonprofitcheckplus.examples.support.Output;
import org.pactman.nonprofitcheckplus.examples.support.Screening;
import org.pactman.nonprofitcheckplus.models.BulkCheckResult;
import org.pactman.nonprofitcheckplus.models.Nonprofit;

/**
 * EX-17 — Screening a batch in one request.
 *
 * <p>One bulk call instead of a loop of single checks: fewer round trips, one
 * rate-limit interaction, and one place to read the usage counter.
 */
public final class Ex17BulkScreening implements Example {

    @Override
    public String id() {
        return "ex-17";
    }

    @Override
    public String title() {
        return "Screening a batch of EINs in one request";
    }

    @Override
    public void run(String[] args) {
        List<String> eins = Arrays.asList(
                FixtureEins.PUBLIC_CHARITY,
                FixtureEins.PUBLIC_CHARITY_SECOND,
                FixtureEins.REVOKED,
                FixtureEins.OFAC_MATCH,
                FixtureEins.CONFLICTED);

        try (ExampleContext context = ExampleContext.withFixtures()) {
            BulkCheckResult result = context.client().nonprofits().checkBulk(eins);

            Output.heading("What came back");
            Output.field("requested", eins.size());
            Output.field("organizations", result.getOrganizations().size());
            Output.field("notFoundEins", result.getNotFoundEins());
            Output.field("checkCount", result.getCheckCount());

            // The response is not ordered to match the request, so pair by EIN.
            // Never by position.
            Map<String, Nonprofit> byEin = new LinkedHashMap<>();

            for (Nonprofit organization : result.getOrganizations()) {
                byEin.put(organization.getEin(), organization);
            }

            for (String ein : eins) {
                Nonprofit organization = byEin.get(ein);

                Output.heading(ein + (organization == null
                        ? " — no record"
                        : " — " + organization.getOrganizationName()));

                if (organization == null) {
                    continue;
                }

                List<String> findings = Screening.findings(organization);

                if (findings.isEmpty()) {
                    Output.bullet("nothing to report");
                } else {
                    for (String finding : findings) {
                        Output.bullet(finding);
                    }
                }
            }
        }

        Output.note("The findings above are what the API said. Not one of them is a decision:\n"
                + "no approved, no eligible, no safe. Which of them stops a payment is your\n"
                + "policy, and ex-26 to ex-30 show four workflows reading the same evidence and\n"
                + "reaching different, defensible conclusions.");
    }
}
