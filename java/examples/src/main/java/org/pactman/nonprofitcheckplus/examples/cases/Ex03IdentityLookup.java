package org.pactman.nonprofitcheckplus.examples.cases;

import org.pactman.nonprofitcheckplus.devtools.FixtureEins;
import org.pactman.nonprofitcheckplus.examples.support.Example;
import org.pactman.nonprofitcheckplus.examples.support.ExampleContext;
import org.pactman.nonprofitcheckplus.examples.support.Output;
import org.pactman.nonprofitcheckplus.models.Nonprofit;
import org.pactman.nonprofitcheckplus.models.SingleCheckResult;

/**
 * EX-03 — Identity lookup.
 *
 * <p>Reads the identity fields off a record, and shows the difference the SDK
 * keeps and most callers lose: a field the API returned as {@code null} is not
 * the same as a field the API did not return at all.
 */
public final class Ex03IdentityLookup implements Example {

    @Override
    public String id() {
        return "ex-03";
    }

    @Override
    public String title() {
        return "Identity fields, and absent versus null";
    }

    @Override
    public void run(String[] args) {
        try (ExampleContext context = ExampleContext.withFixtures()) {
            for (String ein : new String[] {
                FixtureEins.PUBLIC_CHARITY, FixtureEins.SPARSE_IDENTITY
            }) {
                SingleCheckResult result = context.client().nonprofits().check(ein);
                Nonprofit nonprofit = result.getNonprofit();

                Output.heading("EIN " + ein);

                for (String field : new String[] {
                    "organization_name", "organization_name_aka", "address_line1",
                    "address_line2", "city", "state", "state_name", "zip",
                    "pub78_city", "pub78_state", "ofac_status"
                }) {
                    // present() reports <not returned> for a key the API omitted
                    // and <null> for one it sent empty. Two different facts.
                    Output.field(field, Output.present(nonprofit, field));
                }

                Output.field("HTTP status", result.getStatus());
                Output.field("Correlation id", result.getRequestId());
            }
        }

        Output.note("The second record is missing `ofac_status` entirely and returns null for\n"
                + "several identity fields. `has(field)` is what separates the two, and the\n"
                + "distinction matters: \"the source reported nothing\" and \"the source\n"
                + "reported no value\" are different findings, and only one of them is about\n"
                + "the organization.");
    }
}
