package org.pactman.nonprofitcheckplus.examples.cases;

import org.pactman.nonprofitcheckplus.Sources;
import org.pactman.nonprofitcheckplus.devtools.FixtureEins;
import org.pactman.nonprofitcheckplus.examples.support.Example;
import org.pactman.nonprofitcheckplus.examples.support.ExampleContext;
import org.pactman.nonprofitcheckplus.examples.support.Output;
import org.pactman.nonprofitcheckplus.models.BmfSource;
import org.pactman.nonprofitcheckplus.models.Nonprofit;

/**
 * EX-12 — Foundation classification.
 *
 * <p>Public charity or private foundation is the distinction that drives
 * deductibility limits, excise taxes and expenditure responsibility. The API
 * returns both the code and its description; prefer the description, because it
 * comes from the source and changes with it.
 */
public final class Ex12FoundationClassification implements Example {

    @Override
    public String id() {
        return "ex-12";
    }

    @Override
    public String title() {
        return "Public charity versus private foundation";
    }

    @Override
    public void run(String[] args) {
        try (ExampleContext context = ExampleContext.withFixtures()) {
            for (String ein : new String[] {
                FixtureEins.PUBLIC_CHARITY, FixtureEins.PRIVATE_FOUNDATION
            }) {
                Nonprofit nonprofit = context.client().nonprofits().check(ein).getNonprofit();
                BmfSource bmf = Sources.bmf(nonprofit);

                Output.heading(nonprofit.getOrganizationName() + " (" + ein + ")");
                Output.field("subsection", bmf.getSubsection());
                Output.field("subsection_description", bmf.getSubsectionDescription());
                Output.field("foundation_code", bmf.getFoundationCode());
                Output.field("foundation_code_description", bmf.getFoundationCodeDescription());
                Output.field("foundation_type_code", bmf.getFoundationTypeCode());
                Output.field("foundation_type_description", bmf.getFoundationTypeDescription());
                Output.field("foundation_509a_status", bmf.getFoundation509aStatus());
            }
        }

        Output.note("Read the *_description fields rather than mapping the codes yourself. They\n"
                + "arrive from the IRS extract, so a classification the IRS adds is described\n"
                + "correctly the day it appears — a local table would need an SDK release, and\n"
                + "in the meantime would either say nothing or say the wrong thing.\n\n"
                + "Both codes and descriptions can be null. A missing classification is not a\n"
                + "public charity by default.");
    }
}
