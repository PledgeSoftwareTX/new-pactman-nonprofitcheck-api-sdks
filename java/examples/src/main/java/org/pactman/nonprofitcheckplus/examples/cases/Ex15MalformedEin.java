package org.pactman.nonprofitcheckplus.examples.cases;

import java.util.Arrays;
import org.pactman.nonprofitcheckplus.examples.support.Example;
import org.pactman.nonprofitcheckplus.examples.support.ExampleContext;
import org.pactman.nonprofitcheckplus.examples.support.ExampleFailedException;
import org.pactman.nonprofitcheckplus.examples.support.Output;
import org.pactman.nonprofitcheckplus.exceptions.ErrorOrigin;
import org.pactman.nonprofitcheckplus.exceptions.PactmanValidationException;
import org.pactman.nonprofitcheckplus.exceptions.ValidationIssue;

/**
 * EX-15 — A malformed EIN never reaches the API.
 *
 * <p>Local validation is not a convenience. Every request is billable, and a
 * request that cannot succeed should not be one of them.
 */
public final class Ex15MalformedEin implements Example {

    @Override
    public String id() {
        return "ex-15";
    }

    @Override
    public String title() {
        return "Malformed input fails locally, before a billable request";
    }

    @Override
    public void run(String[] args) {
        try (ExampleContext context = ExampleContext.withFixtures()) {
            Output.heading("A single malformed EIN");

            try {
                context.client().nonprofits().check("4117870");
                throw new ExampleFailedException("The malformed EIN should have been rejected.");
            } catch (PactmanValidationException failure) {
                Output.field("exception", failure.getClass().getSimpleName());
                Output.field("category", failure.category());
                Output.field("origin", failure.origin());
                Output.field("message", failure.getMessage());
            }

            Output.heading("A batch with two bad rows");

            try {
                context.client()
                        .nonprofits()
                        .checkBulk(Arrays.asList("411787097", "nope", "996589560", "1234"));
                throw new ExampleFailedException("The batch should have been rejected.");
            } catch (PactmanValidationException failure) {
                Output.field("message", failure.getMessage());
                System.out.println();

                for (ValidationIssue issue : failure.issues()) {
                    Output.bullet("index " + issue.index() + " (" + issue.value() + "): "
                            + issue.message());

                    if (issue.index() == null) {
                        throw new ExampleFailedException(
                                "A batch issue should name the row it came from.");
                    }
                }

                if (failure.origin() != ErrorOrigin.LOCAL) {
                    throw new ExampleFailedException("Local validation should have origin LOCAL.");
                }
            }
        }

        Output.note("origin is what separates these from an API-side rejection. A\n"
                + "PactmanValidationException with origin LOCAL means nothing was sent and\n"
                + "nothing was billed; a PactmanBadRequestException with origin API means the\n"
                + "API looked at the request and refused it. Retrying the first is pointless\n"
                + "until the input changes, which is why neither is ever retried.");
    }
}
