package org.pactman.nonprofitcheckplus.examples.cases;

import org.pactman.nonprofitcheckplus.Sources;
import org.pactman.nonprofitcheckplus.devtools.FixtureEins;
import org.pactman.nonprofitcheckplus.examples.support.Example;
import org.pactman.nonprofitcheckplus.examples.support.ExampleContext;
import org.pactman.nonprofitcheckplus.examples.support.Output;
import org.pactman.nonprofitcheckplus.examples.support.Screening;
import org.pactman.nonprofitcheckplus.models.Nonprofit;
import org.pactman.nonprofitcheckplus.models.OfacSource;

/**
 * EX-10 — OFAC screening.
 *
 * <p>The API reports OFAC as a sentence, not a flag. This SDK does not invent a
 * boolean from it, because deriving one means pattern-matching English that can
 * be reworded at any time. This example does the pattern matching — in your
 * code, where you can see it and own it — and shows the four states it can end
 * in, one of which is "I do not recognize this wording".
 */
public final class Ex10OfacScreening implements Example {

    @Override
    public String id() {
        return "ex-10";
    }

    @Override
    public String title() {
        return "OFAC screening, and the four states it can be in";
    }

    @Override
    public void run(String[] args) {
        try (ExampleContext context = ExampleContext.withFixtures()) {
            for (String ein : new String[] {
                FixtureEins.PUBLIC_CHARITY,
                FixtureEins.OFAC_MATCH,
                FixtureEins.OFAC_UNAVAILABLE,
                FixtureEins.SPARSE_IDENTITY,
            }) {
                Nonprofit nonprofit = context.client().nonprofits().check(ein).getNonprofit();
                OfacSource ofac = Sources.ofac(nonprofit);

                Output.heading(nonprofit.getOrganizationName() + " (" + ein + ")");
                Output.field("Sources.ofac(...)", ofac == null ? null : "returned");
                Output.field("has(\"ofac_status\")", nonprofit.has("ofac_status"));
                Output.field("state", Screening.ofacState(nonprofit));
                System.out.println();
                System.out.println("  " + Output.render(
                        nonprofit.has("ofac_status") ? nonprofit.getOfacStatus() : Output.ABSENT));
            }
        }

        Output.note("Four states, and only one of them is a pass:\n"
                + "  NO_MATCH     — the API said the organization was not on the SDN list\n"
                + "  MATCH        — the API named a possible match, with a UID\n"
                + "  NULL         — the field came back with no value\n"
                + "  UNAVAILABLE  — the API returned no OFAC data at all\n\n"
                + "UNAVAILABLE and NULL are not clean results. They are the absence of a\n"
                + "result, and a screening workflow that treats them as clean has screened\n"
                + "nothing. UNRECOGNIZED — wording this reader does not know — belongs with\n"
                + "them: route it to a person rather than guessing.");
    }
}
