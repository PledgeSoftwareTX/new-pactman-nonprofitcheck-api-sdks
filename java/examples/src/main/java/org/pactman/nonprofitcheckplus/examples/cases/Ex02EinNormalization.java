package org.pactman.nonprofitcheckplus.examples.cases;

import java.util.Arrays;
import java.util.List;
import org.pactman.nonprofitcheckplus.Ein;
import org.pactman.nonprofitcheckplus.examples.support.Example;
import org.pactman.nonprofitcheckplus.examples.support.ExampleFailedException;
import org.pactman.nonprofitcheckplus.examples.support.Output;
import org.pactman.nonprofitcheckplus.exceptions.PactmanValidationException;
import org.pactman.nonprofitcheckplus.exceptions.ValidationIssue;

/**
 * EX-02 — EIN normalization and validation.
 *
 * <p>Every accepted spelling of an EIN, every rejected one, and what the SDK
 * says about each. No request is sent: this all happens locally, which is the
 * point — a malformed EIN should never cost a billable call.
 */
public final class Ex02EinNormalization implements Example {

    @Override
    public String id() {
        return "ex-02";
    }

    @Override
    public String title() {
        return "EIN normalization and local validation";
    }

    @Override
    public void run(String[] args) {
        Output.heading("Accepted spellings");

        for (String input : Arrays.asList("411787097", "41-1787097", "  41-1787097  ")) {
            Output.field("\"" + input + "\"", Ein.normalize(input));
        }

        Output.heading("Rejected values");

        for (String input : Arrays.asList(
                "41178709", "4117870977", "41-178709", "41 1787097", "abcdefghi", "", null)) {
            String label = input == null ? "null" : "\"" + input + "\"";

            try {
                Ein.normalize(input);
                throw new ExampleFailedException(label + " should not have been accepted.");
            } catch (PactmanValidationException failure) {
                Output.field(label, failure.getMessage(), 16);
            }
        }

        // A batch reports every failure at once, by index, so a caller fixes one
        // upload rather than discovering the next bad row on the next attempt.
        Output.heading("A batch reports every failure at once");

        List<String> batch = Arrays.asList("411787097", "nope", "996589560", "1234");

        try {
            Ein.normalizeAll(batch);
            throw new ExampleFailedException("The batch should have been rejected.");
        } catch (PactmanValidationException failure) {
            System.out.println("  " + failure.getMessage());
            System.out.println();

            for (ValidationIssue issue : failure.issues()) {
                Output.bullet("index " + issue.index() + ": " + issue.value()
                        + " — " + issue.message());
            }
        }

        Output.heading("What validation does not tell you");
        Output.field("Ein.isValid(\"00-0000000\")", Ein.isValid("00-0000000"));

        Output.note("Formatting validation confirms only that a value is shaped like an EIN.\n"
                + "It says nothing about tax-exempt status, identity, eligibility, or good\n"
                + "standing. No IRS prefix rules are applied.");
    }
}
