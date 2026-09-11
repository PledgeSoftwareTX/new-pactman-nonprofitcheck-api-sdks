package org.pactman.nonprofitcheckplus.examples.cases;

import org.pactman.nonprofitcheckplus.Sources;
import org.pactman.nonprofitcheckplus.devtools.FixtureEins;
import org.pactman.nonprofitcheckplus.devtools.ApiDate;
import org.pactman.nonprofitcheckplus.examples.support.Example;
import org.pactman.nonprofitcheckplus.examples.support.ExampleContext;
import org.pactman.nonprofitcheckplus.examples.support.Output;
import org.pactman.nonprofitcheckplus.examples.support.Screening;
import org.pactman.nonprofitcheckplus.models.AroeSource;
import org.pactman.nonprofitcheckplus.models.Nonprofit;

/**
 * EX-09 — Revocation followed by reinstatement.
 *
 * <p>A revoked organization can get its exemption back, and the record then
 * carries both dates. Reading only {@code revocation_date} turns a
 * currently-exempt charity into a rejection.
 */
public final class Ex09RevocationReinstatement implements Example {

    @Override
    public String id() {
        return "ex-09";
    }

    @Override
    public String title() {
        return "Revocation and reinstatement, read together";
    }

    @Override
    public void run(String[] args) {
        try (ExampleContext context = ExampleContext.withFixtures()) {
            for (String ein : new String[] {FixtureEins.REVOKED, FixtureEins.REINSTATED}) {
                Nonprofit nonprofit = context.client().nonprofits().check(ein).getNonprofit();
                AroeSource aroe = Sources.aroe(nonprofit);

                Output.heading(nonprofit.getOrganizationName() + " (" + ein + ")");
                Output.field("revocation_date", aroe.getRevocationDate());
                Output.field("reinstatement_date", aroe.getReinstatementDate());
                Output.field(
                        "revoked and not reinstated",
                        Screening.revokedAndNotReinstated(nonprofit));

                Long revokedAge = ApiDate.ageInDays(aroe.getRevocationDate());
                Long reinstatedAge = ApiDate.ageInDays(aroe.getReinstatementDate());

                Output.field("revoked", revokedAge == null ? null : revokedAge + " days ago");
                Output.field(
                        "reinstated",
                        reinstatedAge == null ? null : reinstatedAge + " days ago");

                // Both records carry a revocation date. Only one of them is
                // still revoked, and the fields that say so are the current
                // status fields, not the historical one.
                Output.field("pub78_verified", nonprofit.getPub78Verified());
                Output.field("bmf_status", nonprofit.getBmfStatus());
            }
        }

        Output.note("Both organizations were revoked. One of them is exempt today. A rule that\n"
                + "reads revocation_date alone rejects both — and the reinstated one has been\n"
                + "back in good standing for years. Read the pair, and prefer the current\n"
                + "status fields for the current question.");
    }
}
