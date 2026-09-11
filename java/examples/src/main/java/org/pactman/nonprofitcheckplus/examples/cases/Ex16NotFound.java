package org.pactman.nonprofitcheckplus.examples.cases;

import org.pactman.nonprofitcheckplus.Ein;
import org.pactman.nonprofitcheckplus.devtools.FixtureEins;
import org.pactman.nonprofitcheckplus.examples.support.Example;
import org.pactman.nonprofitcheckplus.examples.support.ExampleContext;
import org.pactman.nonprofitcheckplus.examples.support.ExampleFailedException;
import org.pactman.nonprofitcheckplus.examples.support.Output;
import org.pactman.nonprofitcheckplus.exceptions.PactmanNotFoundException;

/**
 * EX-16 — A well-formed EIN with no record.
 *
 * <p>"Shaped like an EIN" and "an EIN the IRS has a record for" are different
 * questions. The first is answered locally; only the second costs a request, and
 * a miss is an ordinary outcome rather than a fault.
 */
public final class Ex16NotFound implements Example {

    @Override
    public String id() {
        return "ex-16";
    }

    @Override
    public String title() {
        return "A valid EIN the API has no record for";
    }

    @Override
    public void run(String[] args) {
        String ein = FixtureEins.NO_RECORD;

        Output.heading("Locally, this EIN is fine");
        Output.field("Ein.isValid", Ein.isValid(ein));
        Output.field("Ein.normalize", Ein.normalize(ein));

        try (ExampleContext context = ExampleContext.withFixtures()) {
            Output.heading("The API has no record for it");

            try {
                context.client().nonprofits().check(ein);
                throw new ExampleFailedException("Expected the lookup to report no record.");
            } catch (PactmanNotFoundException failure) {
                Output.field("exception", failure.getClass().getSimpleName());
                Output.field("category", failure.category());
                Output.field("origin", failure.origin());
                Output.field("status", failure.status());
                Output.field("message", failure.getMessage());
                Output.field("requestId", failure.requestId());
                Output.field("attempts", failure.attempts());
            }
        }

        Output.note("A single check with no record is an HTTP 404, and the SDK raises it as\n"
                + "PactmanNotFoundException — which is never retried, because the answer will\n"
                + "not change on a second attempt.\n\n"
                + "Bulk behaves differently on purpose: a batch where some EINs matched is a\n"
                + "200, with the misses listed in getNotFoundEins(). See ex-19.\n\n"
                + "No record is not evidence that an organization does not exist. It is the\n"
                + "absence of a record in the extracts behind this API.");
    }
}
