package org.pactman.nonprofitcheckplus.examples.cases;

import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import org.pactman.nonprofitcheckplus.Endpoints;
import org.pactman.nonprofitcheckplus.devtools.FixtureEins;
import org.pactman.nonprofitcheckplus.examples.support.Example;
import org.pactman.nonprofitcheckplus.examples.support.ExampleContext;
import org.pactman.nonprofitcheckplus.examples.support.ExampleFailedException;
import org.pactman.nonprofitcheckplus.examples.support.Output;
import org.pactman.nonprofitcheckplus.exceptions.PactmanValidationException;
import org.pactman.nonprofitcheckplus.models.BulkCheckResult;

/**
 * EX-20 — The batch limit, and chunking a larger list yourself.
 *
 * <p>The SDK will not split an oversized batch for you. Splitting turns one call
 * a caller intended into several billable calls they did not, so it is a
 * decision the caller makes.
 */
public final class Ex20BulkBatchLimits implements Example {

    @Override
    public String id() {
        return "ex-20";
    }

    @Override
    public String title() {
        return "The 50-EIN batch limit, and chunking on your own terms";
    }

    @Override
    public void run(String[] args) {
        try (ExampleContext context = ExampleContext.withFixtures()) {
            Output.heading("The limit is enforced locally");
            Output.field("Endpoints.MAX_BULK_EINS", Endpoints.MAX_BULK_EINS);

            List<String> tooMany =
                    new ArrayList<>(Collections.nCopies(
                            Endpoints.MAX_BULK_EINS + 1, FixtureEins.PUBLIC_CHARITY));

            try {
                context.client().nonprofits().checkBulk(tooMany);
                throw new ExampleFailedException("An oversized batch should have been rejected.");
            } catch (PactmanValidationException failure) {
                Output.field("sent", 0);
                Output.field("message", failure.getMessage());
            }

            Output.heading("Chunking a larger list");

            // A real workload would hold hundreds of EINs. Chunking is four
            // lines, and doing it here means the caller can see how many
            // billable requests they are about to make.
            List<String> everything = new ArrayList<>();

            for (int i = 0; i < 6; i++) {
                everything.addAll(java.util.Arrays.asList(
                        FixtureEins.PUBLIC_CHARITY,
                        FixtureEins.PUBLIC_CHARITY_SECOND,
                        FixtureEins.PRIVATE_FOUNDATION));
            }

            int batchSize = 5;
            int batches = 0;
            int matched = 0;

            for (int start = 0; start < everything.size(); start += batchSize) {
                List<String> chunk =
                        everything.subList(start, Math.min(start + batchSize, everything.size()));
                BulkCheckResult result = context.client().nonprofits().checkBulk(chunk);
                batches += 1;
                matched += result.getOrganizations().size();
            }

            Output.field("EINs", everything.size());
            Output.field("batch size", batchSize);
            Output.field("requests made", batches);
            Output.field("organizations returned", matched);
        }

        Output.note("The batch size above is 5 to keep the example short; the API's limit is 50\n"
                + "and a real workload should use it. Note that duplicates within a chunk are\n"
                + "still sent — pass dedupe(true), or clean the input, if the list came from\n"
                + "somewhere you do not control.");
    }
}
