package org.pactman.nonprofitcheckplus.examples.cases;

import org.pactman.nonprofitcheckplus.Sources;
import org.pactman.nonprofitcheckplus.devtools.FixtureEins;
import org.pactman.nonprofitcheckplus.examples.support.Example;
import org.pactman.nonprofitcheckplus.examples.support.ExampleContext;
import org.pactman.nonprofitcheckplus.examples.support.IrsCodes;
import org.pactman.nonprofitcheckplus.examples.support.Output;
import org.pactman.nonprofitcheckplus.models.Nonprofit;
import org.pactman.nonprofitcheckplus.models.OrganizationType;
import org.pactman.nonprofitcheckplus.models.Pub78Source;

/**
 * EX-07 — Publication 78 and deductibility limits.
 *
 * <p>Publication 78 is what says a donation is deductible, and
 * {@code organization_types} carries the limit that applies. A public charity
 * and a private foundation differ here, and the difference is the donor's tax
 * outcome.
 */
public final class Ex07Pub78Deductibility implements Example {

    @Override
    public String id() {
        return "ex-07";
    }

    @Override
    public String title() {
        return "Publication 78 listing and deductibility limits";
    }

    @Override
    public void run(String[] args) {
        try (ExampleContext context = ExampleContext.withFixtures()) {
            for (String ein : new String[] {
                FixtureEins.PUBLIC_CHARITY, FixtureEins.PRIVATE_FOUNDATION, FixtureEins.REVOKED
            }) {
                Nonprofit nonprofit = context.client().nonprofits().check(ein).getNonprofit();
                Pub78Source pub78 = Sources.pub78(nonprofit);

                Output.heading(nonprofit.getOrganizationName() + " (" + ein + ")");

                if (pub78 == null) {
                    Output.bullet("The API returned no Publication 78 data at all.");
                    continue;
                }

                Output.field("verified", pub78.getVerified());
                Output.field("indicator", pub78.getIndicator());
                Output.field(
                        "  meaning", IrsCodes.describePub78Indicator(pub78.getIndicator()));
                Output.field("most_recent", pub78.getMostRecent());
                Output.field("organization_types", pub78.getOrganizationTypes());

                for (OrganizationType type : pub78.getOrganizationTypes()) {
                    System.out.println();
                    Output.field("  limitation", type.getDeductibilityLimitation());
                    Output.field("  status", type.getDeductibilityStatusDescription());
                    Output.field("  text", truncate(type.getOrganizationType()));
                }
            }
        }

        Output.note("organization_types is empty for the revoked organization — the API sent\n"
                + "null, not an empty list. getOrganizationTypes() returns an empty list either\n"
                + "way so iterating is always safe; ask has(\"organization_types\") when the\n"
                + "difference matters.\n\n"
                + "Deductibility is the donor's tax question, not the charity's status. Read the\n"
                + "limit the API returned; do not infer one from the subsection.");
    }

    private static String truncate(String text) {
        if (text == null) {
            return null;
        }

        return text.length() <= 72 ? text : text.substring(0, 69) + "...";
    }
}
