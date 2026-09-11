package org.pactman.nonprofitcheckplus.examples.cases;

import java.util.Arrays;
import org.pactman.nonprofitcheckplus.devtools.FixtureEins;
import org.pactman.nonprofitcheckplus.examples.support.Example;
import org.pactman.nonprofitcheckplus.examples.support.ExampleContext;
import org.pactman.nonprofitcheckplus.examples.support.Output;
import org.pactman.nonprofitcheckplus.models.BulkCheckResult;
import org.pactman.nonprofitcheckplus.models.SingleCheckResult;

/**
 * EX-21 — Usage tracking.
 *
 * <p>{@code checkCount} is a running total for the billing cycle, not the size
 * of the request that returned it. Reading it as a per-request cost is the
 * single most common way to misreport usage.
 */
public final class Ex21UsageTracking implements Example {

    @Override
    public String id() {
        return "ex-21";
    }

    @Override
    public String title() {
        return "What checkCount means, and how to measure a request";
    }

    @Override
    public void run(String[] args) {
        try (ExampleContext context = ExampleContext.withFixtures()) {
            SingleCheckResult first = context.client()
                    .nonprofits()
                    .check(FixtureEins.PUBLIC_CHARITY);

            Output.heading("A single check");
            Output.field("checkCount", first.getCheckCount());
            Output.field("timeTakenMs", first.getTimeTakenMs());

            BulkCheckResult batch = context.client()
                    .nonprofits()
                    .checkBulk(Arrays.asList(
                            FixtureEins.PUBLIC_CHARITY,
                            FixtureEins.PUBLIC_CHARITY_SECOND,
                            FixtureEins.PRIVATE_FOUNDATION,
                            FixtureEins.NO_RECORD));

            Output.heading("A batch of four, one of which has no record");
            Output.field("EINs sent", 4);
            Output.field("organizations returned", batch.getOrganizations().size());
            Output.field("notFoundEins", batch.getNotFoundEins());
            Output.field("checkCount", batch.getCheckCount());

            Output.heading("What the batch actually consumed");
            Output.field("count before", first.getCheckCount());
            Output.field("count after", batch.getCheckCount());
            Output.field(
                    "delta",
                    batch.getCheckCount() == null || first.getCheckCount() == null
                            ? null
                            : batch.getCheckCount() - first.getCheckCount());
        }

        Output.note("Four EINs went out and the counter moved by three, because the EIN with no\n"
                + "record was not billed. Two consequences:\n\n"
                + "  - the size of your batch is not its cost\n"
                + "  - a delta between two responses is, and it is the only number that is\n\n"
                + "The counter resets when a new billing cycle begins, so a delta across that\n"
                + "boundary is meaningless. Read the value the API reports rather than keeping\n"
                + "your own running total.");
    }
}
