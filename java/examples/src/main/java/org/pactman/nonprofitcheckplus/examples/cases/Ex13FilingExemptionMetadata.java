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
 * EX-13 — Filing and exemption metadata.
 *
 * <p>The codes the API returns bare — filing requirement, exempt status — are
 * the ones that need a local table. This example shows the table, and the two
 * rules that keep one safe to own.
 */
public final class Ex13FilingExemptionMetadata implements Example {

    @Override
    public String id() {
        return "ex-13";
    }

    @Override
    public String title() {
        return "Filing requirement, exempt status, and describing bare codes";
    }

    @Override
    public void run(String[] args) {
        try (ExampleContext context = ExampleContext.withFixtures()) {
            for (String ein : new String[] {
                FixtureEins.PUBLIC_CHARITY, FixtureEins.PRIVATE_FOUNDATION, FixtureEins.REVOKED
            }) {
                Nonprofit nonprofit = context.client().nonprofits().check(ein).getNonprofit();
                BmfSource bmf = Sources.bmf(nonprofit);

                Output.heading(nonprofit.getOrganizationName() + " (" + ein + ")");
                Output.field("filing_req_code", bmf.getFilingReqCode());
                Output.field(
                        "  meaning", IrsCodes.describeFilingRequirement(bmf.getFilingReqCode()));
                Output.field("exempt_status_code", bmf.getExemptStatusCode());
                Output.field("  meaning", IrsCodes.describeExemptStatus(bmf.getExemptStatusCode()));
                Output.field("group_exemption", bmf.getGroupExemption());
                Output.field("ruling_month", bmf.getRulingMonth());
                Output.field("ruling_year", bmf.getRulingYear());
            }

            Output.heading("What an unknown code does");
            Output.field("code \"99\"", IrsCodes.describeFilingRequirement("99"));
            Output.field("code null", IrsCodes.describeFilingRequirement(null));
        }

        Output.note("Two rules make a local code table safe:\n\n"
                + "  1. An unknown code degrades to a sentence that keeps the code visible,\n"
                + "     never to null and never to a wrong label. A value the IRS adds is then\n"
                + "     legible to whoever reads the output, without an SDK release.\n"
                + "  2. null stays null. Reporting \"unknown code\" for a field the API never\n"
                + "     sent invents a code, and someone downstream will investigate it.");
    }
}
