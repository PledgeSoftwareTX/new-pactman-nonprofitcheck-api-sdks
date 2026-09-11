package org.pactman.nonprofitcheckplus.examples.cases;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import org.pactman.nonprofitcheckplus.config.BulkRequestOptions;
import org.pactman.nonprofitcheckplus.devtools.FixtureEins;
import org.pactman.nonprofitcheckplus.examples.support.Example;
import org.pactman.nonprofitcheckplus.examples.support.ExampleContext;
import org.pactman.nonprofitcheckplus.examples.support.ExampleFailedException;
import org.pactman.nonprofitcheckplus.examples.support.Output;
import org.pactman.nonprofitcheckplus.models.BulkCheckResult;
import org.pactman.nonprofitcheckplus.models.Nonprofit;

/**
 * EX-18 — Ordering and duplicates in a bulk request.
 *
 * <p>The one pairing rule that always holds: index the response by EIN. The API
 * matches by set membership, so it neither preserves your order nor returns a
 * repeated EIN twice.
 */
public final class Ex18BulkOrderAndDuplicates implements Example {

    @Override
    public String id() {
        return "ex-18";
    }

    @Override
    public String title() {
        return "Request order, response order, and duplicate EINs";
    }

    @Override
    public void run(String[] args) {
        List<String> requested = Arrays.asList(
                FixtureEins.PUBLIC_CHARITY_SECOND,
                FixtureEins.PUBLIC_CHARITY,
                FixtureEins.PUBLIC_CHARITY_SECOND);

        try (ExampleContext context = ExampleContext.withFixtures()) {
            Output.heading("Duplicates are sent as supplied");

            BulkCheckResult asSupplied = context.client().nonprofits().checkBulk(requested);

            Output.field("requested", requested);
            Output.field("organizations returned", asSupplied.getOrganizations().size());

            List<String> returned = new ArrayList<>();

            for (Nonprofit organization : asSupplied.getOrganizations()) {
                returned.add(organization.getEin());
            }

            Output.field("EINs returned", returned);

            if (returned.size() == requested.size()) {
                throw new ExampleFailedException(
                        "The API should have collapsed the repeated EIN into one record.");
            }

            Output.heading("Deduplicating before sending");

            BulkCheckResult deduped = context.client()
                    .nonprofits()
                    .checkBulk(requested, new BulkRequestOptions().dedupe(true));

            Output.field("organizations returned", deduped.getOrganizations().size());
        }

        Output.note("Three EINs went out and two records came back, because the API matches by\n"
                + "set membership. Pairing the response with the request by position would have\n"
                + "attributed the second organization's findings to the third row.\n\n"
                + "Duplicates are sent as supplied by default, because each one is billable and\n"
                + "silently dropping them would misreport what was checked. dedupe(true) is the\n"
                + "opt-in, and it is the right call when your input is a CSV nobody cleaned.");
    }
}
