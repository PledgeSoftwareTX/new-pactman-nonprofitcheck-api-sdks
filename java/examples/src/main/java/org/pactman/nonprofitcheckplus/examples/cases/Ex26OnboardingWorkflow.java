package org.pactman.nonprofitcheckplus.examples.cases;

import java.util.List;
import org.pactman.nonprofitcheckplus.devtools.FixtureEins;
import org.pactman.nonprofitcheckplus.examples.support.Addresses;
import org.pactman.nonprofitcheckplus.examples.support.Example;
import org.pactman.nonprofitcheckplus.examples.support.ExampleContext;
import org.pactman.nonprofitcheckplus.examples.support.Matching;
import org.pactman.nonprofitcheckplus.examples.support.Output;
import org.pactman.nonprofitcheckplus.examples.support.Screening;
import org.pactman.nonprofitcheckplus.exceptions.PactmanNotFoundException;
import org.pactman.nonprofitcheckplus.models.Nonprofit;

/**
 * EX-26 — Onboarding a nonprofit to a giving platform.
 *
 * <p>An applicant types a name and an EIN. This workflow decides one thing:
 * whether a human needs to look at the application. It never decides whether the
 * organization is legitimate.
 */
public final class Ex26OnboardingWorkflow implements Example {

    /** One applicant, as they typed it. */
    private static final String[][] APPLICANTS = {
        {FixtureEins.PUBLIC_CHARITY, "Meals Today Example Nonprofit Inc."},
        {FixtureEins.REVOKED, "Lapsed Filings Example Society"},
        {FixtureEins.INCONSISTENT_ADDRESS, "Harbour Light Example Alliance"},
        {FixtureEins.NO_RECORD, "Brand New Example Charity"},
    };

    @Override
    public String id() {
        return "ex-26";
    }

    @Override
    public String title() {
        return "Onboarding: routing an application to review or to a reviewer";
    }

    @Override
    public void run(String[] args) {
        try (ExampleContext context = ExampleContext.withFixtures()) {
            for (String[] applicant : APPLICANTS) {
                String ein = applicant[0];
                String typedName = applicant[1];

                Output.heading(typedName + " (" + ein + ")");

                Nonprofit nonprofit;

                try {
                    nonprofit = context.client().nonprofits().check(ein).getNonprofit();
                } catch (PactmanNotFoundException noRecord) {
                    Output.bullet("No IRS record for this EIN.");
                    Output.field("routing", "MANUAL REVIEW — cannot verify without a record");
                    continue;
                }

                Matching.Comparison nameCheck =
                        Matching.compareNames(typedName, nonprofit.getOrganizationName());
                List<String> screening = Screening.findings(nonprofit);
                List<String> address = Addresses.findings(nonprofit);

                Output.field("IRS name", nonprofit.getOrganizationName());
                Output.field("name comparison", nameCheck);

                for (String finding : screening) {
                    Output.bullet(finding);
                }

                for (String finding : address) {
                    Output.bullet(finding);
                }

                // The policy, stated in one place so it can be argued with.
                boolean needsReview = nameCheck != Matching.Comparison.AGREE
                        || !screening.isEmpty()
                        || !address.isEmpty();

                Output.field(
                        "routing",
                        needsReview ? "MANUAL REVIEW" : "PROCEED under this platform's policy");
            }
        }

        Output.note("Every branch above is this platform's policy, not the SDK's and not the\n"
                + "API's. A different platform reading identical responses would route them\n"
                + "differently and would also be right.\n\n"
                + "Note what the workflow does with a missing record: it asks for a human, not\n"
                + "a rejection. Absence of a record is not evidence of anything.");
    }
}
