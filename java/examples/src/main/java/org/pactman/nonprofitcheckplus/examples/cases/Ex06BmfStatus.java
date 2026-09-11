package org.pactman.nonprofitcheckplus.examples.cases;

import org.pactman.nonprofitcheckplus.Sources;
import org.pactman.nonprofitcheckplus.devtools.FixtureEins;
import org.pactman.nonprofitcheckplus.examples.support.Example;
import org.pactman.nonprofitcheckplus.examples.support.ExampleContext;
import org.pactman.nonprofitcheckplus.examples.support.IrsCodes;
import org.pactman.nonprofitcheckplus.examples.support.Output;
import org.pactman.nonprofitcheckplus.models.BmfSource;
import org.pactman.nonprofitcheckplus.models.Nonprofit;

/**
 * EX-06 — Reading the IRS Business Master File finding.
 *
 * <p>{@code bmf_status} is the closest thing the API has to "the IRS lists this
 * organization as exempt". It is still one source among four, and it has three
 * states, not two.
 */
public final class Ex06BmfStatus implements Example {

    @Override
    public String id() {
        return "ex-06";
    }

    @Override
    public String title() {
        return "The Business Master File finding, and its three states";
    }

    @Override
    public void run(String[] args) {
        try (ExampleContext context = ExampleContext.withFixtures()) {
            for (String ein : new String[] {FixtureEins.PUBLIC_CHARITY, FixtureEins.REVOKED}) {
                Nonprofit nonprofit = context.client().nonprofits().check(ein).getNonprofit();
                BmfSource bmf = Sources.bmf(nonprofit);

                Output.heading(nonprofit.getOrganizationName() + " (" + ein + ")");

                if (bmf == null) {
                    Output.bullet("The API returned no Business Master File data at all.");
                    continue;
                }

                Output.field("status", bmf.getStatus());
                Output.field("subsection", bmf.getSubsection());
                Output.field("subsection_description", bmf.getSubsectionDescription());
                Output.field("exempt_status_code", bmf.getExemptStatusCode());
                Output.field(
                        "  meaning",
                        IrsCodes.describeExemptStatus(bmf.getExemptStatusCode()));
                Output.field("ruling", bmf.getRulingMonth() + "/" + bmf.getRulingYear());
                Output.field("most_recent_bmf", bmf.getMostRecent());
            }
        }

        Output.note("bmf_status has three states, and a boolean cast collapses one of them:\n"
                + "  true  — the BMF lists the organization as exempt\n"
                + "  false — the BMF has a record and it is not exempt\n"
                + "  null  — the BMF said nothing either way\n"
                + "Only the first is a positive finding. Treating null as false invents a\n"
                + "negative the IRS never gave you.");
    }
}
