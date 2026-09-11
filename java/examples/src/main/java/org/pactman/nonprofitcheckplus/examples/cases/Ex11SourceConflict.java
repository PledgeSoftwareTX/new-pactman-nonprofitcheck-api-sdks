package org.pactman.nonprofitcheckplus.examples.cases;

import org.pactman.nonprofitcheckplus.Sources;
import org.pactman.nonprofitcheckplus.devtools.FixtureEins;
import org.pactman.nonprofitcheckplus.examples.support.Example;
import org.pactman.nonprofitcheckplus.examples.support.ExampleContext;
import org.pactman.nonprofitcheckplus.examples.support.Output;
import org.pactman.nonprofitcheckplus.models.BmfSource;
import org.pactman.nonprofitcheckplus.models.Nonprofit;
import org.pactman.nonprofitcheckplus.models.Pub78Source;

/**
 * EX-11 — When the sources disagree.
 *
 * <p>The BMF and Publication 78 are separate IRS extracts, published on
 * different schedules. They can disagree, and the API says so with
 * {@code irs_bmf_pub78_conflict} rather than picking a winner. Neither should
 * this SDK, and neither should a workflow that silently prefers one.
 */
public final class Ex11SourceConflict implements Example {

    @Override
    public String id() {
        return "ex-11";
    }

    @Override
    public String title() {
        return "A BMF and Publication 78 disagreement";
    }

    @Override
    public void run(String[] args) {
        try (ExampleContext context = ExampleContext.withFixtures()) {
            for (String ein : new String[] {FixtureEins.PUBLIC_CHARITY, FixtureEins.CONFLICTED}) {
                Nonprofit nonprofit = context.client().nonprofits().check(ein).getNonprofit();
                Pub78Source pub78 = Sources.pub78(nonprofit);
                BmfSource bmf = Sources.bmf(nonprofit);

                Output.heading(nonprofit.getOrganizationName() + " (" + ein + ")");
                Output.field("irs_bmf_pub78_conflict", nonprofit.getIrsBmfPub78Conflict());
                Output.field("bmf_status", bmf == null ? Output.ABSENT : bmf.getStatus());
                Output.field(
                        "bmf_organization_name",
                        bmf == null ? Output.ABSENT : bmf.getOrganizationName());
                Output.field("most_recent_bmf", bmf == null ? Output.ABSENT : bmf.getMostRecent());
                Output.field("pub78_verified", pub78 == null ? Output.ABSENT : pub78.getVerified());
                Output.field(
                        "pub78_organization_name",
                        pub78 == null ? Output.ABSENT : pub78.getOrganizationName());
                Output.field(
                        "most_recent_pub78", pub78 == null ? Output.ABSENT : pub78.getMostRecent());
            }
        }

        Output.note("The second organization is exempt according to the BMF and unlisted\n"
                + "according to Publication 78. Both statements came from the IRS. The API\n"
                + "flags the disagreement; what to do about it is your policy:\n\n"
                + "  - a donation platform might accept the BMF and note the conflict\n"
                + "  - a DAF issuing a grant might hold it for review\n"
                + "  - a tax-receipt flow cares specifically about Publication 78\n\n"
                + "All three are right for their own obligations, which is exactly why the SDK\n"
                + "does not choose.");
    }
}
