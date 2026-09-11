package org.pactman.nonprofitcheckplus.examples.cases;

import org.pactman.nonprofitcheckplus.Sources;
import org.pactman.nonprofitcheckplus.devtools.FixtureEins;
import org.pactman.nonprofitcheckplus.examples.support.Example;
import org.pactman.nonprofitcheckplus.examples.support.ExampleContext;
import org.pactman.nonprofitcheckplus.examples.support.IrsCodes;
import org.pactman.nonprofitcheckplus.examples.support.Output;
import org.pactman.nonprofitcheckplus.models.AroeSource;
import org.pactman.nonprofitcheckplus.models.Nonprofit;

/**
 * EX-08 — The Automatic Revocation of Exemption list.
 *
 * <p>An organization that fails to file for three consecutive years loses its
 * exemption automatically. The revocation fields say so, and they say it
 * independently of what the BMF and Publication 78 report.
 */
public final class Ex08AutomaticRevocation implements Example {

    @Override
    public String id() {
        return "ex-08";
    }

    @Override
    public String title() {
        return "Automatic revocation, read across every source";
    }

    @Override
    public void run(String[] args) {
        try (ExampleContext context = ExampleContext.withFixtures()) {
            for (String ein : new String[] {FixtureEins.PUBLIC_CHARITY, FixtureEins.REVOKED}) {
                Nonprofit nonprofit = context.client().nonprofits().check(ein).getNonprofit();
                AroeSource aroe = Sources.aroe(nonprofit);

                Output.heading(nonprofit.getOrganizationName() + " (" + ein + ")");

                if (aroe == null) {
                    Output.bullet("The API returned no revocation data at all.");
                    continue;
                }

                Output.field("revocation_code", aroe.getRevocationCode());
                Output.field(
                        "  meaning", IrsCodes.describeRevocationCode(aroe.getRevocationCode()));
                Output.field("revocation_date", aroe.getRevocationDate());
                Output.field("reinstatement_date", aroe.getReinstatementDate());

                // The other sources agree here, and that is worth showing: a
                // revocation is visible in three places, and a workflow that
                // reads only one of them is one API change from missing it.
                Output.field("pub78_verified", nonprofit.getPub78Verified());
                Output.field("bmf_status", nonprofit.getBmfStatus());
                Output.field("exempt_status_code", nonprofit.getExemptStatusCode());
                Output.field(
                        "  meaning",
                        IrsCodes.describeExemptStatus(nonprofit.getExemptStatusCode()));
            }
        }

        Output.note("A revocation date with no reinstatement date is the state worth acting on.\n"
                + "The next example shows why the reinstatement date is not optional reading.");
    }
}
