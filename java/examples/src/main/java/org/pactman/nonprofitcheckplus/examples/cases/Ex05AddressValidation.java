package org.pactman.nonprofitcheckplus.examples.cases;

import java.util.List;
import org.pactman.nonprofitcheckplus.devtools.FixtureEins;
import org.pactman.nonprofitcheckplus.examples.support.Addresses;
import org.pactman.nonprofitcheckplus.examples.support.Example;
import org.pactman.nonprofitcheckplus.examples.support.ExampleContext;
import org.pactman.nonprofitcheckplus.examples.support.Output;
import org.pactman.nonprofitcheckplus.models.Nonprofit;

/**
 * EX-05 — Address validation.
 *
 * <p>A non-null address field is not a usable address. This example runs three
 * records through the same checks: one clean, one with several fields returned
 * as null, and one where every component is present and they contradict each
 * other.
 */
public final class Ex05AddressValidation implements Example {

    @Override
    public String id() {
        return "ex-05";
    }

    @Override
    public String title() {
        return "Address validation beyond a null check";
    }

    @Override
    public void run(String[] args) {
        try (ExampleContext context = ExampleContext.withFixtures()) {
            for (String ein : new String[] {
                FixtureEins.PUBLIC_CHARITY,
                FixtureEins.SPARSE_IDENTITY,
                FixtureEins.INCONSISTENT_ADDRESS,
            }) {
                Nonprofit nonprofit = context.client().nonprofits().check(ein).getNonprofit();

                Output.heading(nonprofit.getOrganizationName() + " (" + ein + ")");
                Output.field("address_line1", Output.present(nonprofit, "address_line1"));
                Output.field("address_line2", Output.present(nonprofit, "address_line2"));
                Output.field("city", Output.present(nonprofit, "city"));
                Output.field("state", Output.present(nonprofit, "state"));
                Output.field("state_name", Output.present(nonprofit, "state_name"));
                Output.field("zip", Output.present(nonprofit, "zip"));

                List<String> findings = Addresses.findings(nonprofit);

                System.out.println();

                if (findings.isEmpty()) {
                    Output.bullet("nothing to report");
                } else {
                    for (String finding : findings) {
                        Output.bullet(finding);
                    }
                }
            }
        }

        Output.note("The third record would pass any check that only asks whether the fields\n"
                + "came back non-null: every component is there. The state code, the spelled-out\n"
                + "state and the ZIP describe three different places, and address_line2 holds a\n"
                + "placeholder. Read the values, not just their presence.");
    }
}
