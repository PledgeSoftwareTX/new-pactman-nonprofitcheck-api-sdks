package org.pactman.nonprofitcheckplus.examples.cases;

import org.pactman.nonprofitcheckplus.Sources;
import org.pactman.nonprofitcheckplus.devtools.FixtureEins;
import org.pactman.nonprofitcheckplus.examples.support.Example;
import org.pactman.nonprofitcheckplus.examples.support.ExampleContext;
import org.pactman.nonprofitcheckplus.examples.support.Matching;
import org.pactman.nonprofitcheckplus.examples.support.Output;
import org.pactman.nonprofitcheckplus.models.Nonprofit;
import org.pactman.nonprofitcheckplus.models.Pub78Source;

/**
 * EX-04 — Comparing an applicant's name against the record.
 *
 * <p>The API returns three names for one organization: the BMF name, the
 * Publication 78 name, and an "also known as". They disagree routinely, and
 * none of them is wrong. Comparing an applicant's typed name against them is a
 * customer policy question, which is why the comparison lives here and not in
 * the SDK.
 */
public final class Ex04NameComparison implements Example {

    @Override
    public String id() {
        return "ex-04";
    }

    @Override
    public String title() {
        return "Comparing an applicant's name against the IRS record";
    }

    @Override
    public void run(String[] args) {
        String applicant = args.length > 0 ? args[0] : "Meals Today Example Nonprofit, Inc.";

        try (ExampleContext context = ExampleContext.withFixtures()) {
            Nonprofit nonprofit = context.client()
                    .nonprofits()
                    .check(FixtureEins.PUBLIC_CHARITY)
                    .getNonprofit();

            Pub78Source pub78 = Sources.pub78(nonprofit);

            Output.heading("The names the API returned");
            Output.field("applicant typed", applicant);
            Output.field("organization_name", nonprofit.getOrganizationName());
            Output.field("bmf_organization_name", nonprofit.getBmfOrganizationName());
            Output.field(
                    "pub78_organization_name",
                    pub78 == null ? Output.ABSENT : pub78.getOrganizationName());
            Output.field("organization_name_aka", nonprofit.getOrganizationNameAka());

            Output.heading("Normalized for comparison");
            Output.field("applicant", Matching.normalizeName(applicant));
            Output.field("organization_name", Matching.normalizeName(nonprofit.getOrganizationName()));

            Output.heading("How each one compares");

            for (String[] candidate : new String[][] {
                {"organization_name", nonprofit.getOrganizationName()},
                {"bmf_organization_name", nonprofit.getBmfOrganizationName()},
                {"pub78_organization_name", pub78 == null ? null : pub78.getOrganizationName()},
                {"organization_name_aka", nonprofit.getOrganizationNameAka()},
            }) {
                Matching.Comparison comparison =
                        Matching.compareNames(applicant, candidate[1]);
                Double overlap = Matching.wordOverlap(applicant, candidate[1]);

                Output.field(
                        candidate[0],
                        comparison + (overlap == null
                                ? ""
                                : String.format(" (word overlap %.2f)", overlap)));
            }
        }

        Output.note("A missing name is UNCOMPARABLE, never agreement — scoring an absent value\n"
                + "as a match is how a blank record passes a name check. And a name that\n"
                + "differs is not fraud: organizations rename, and IRS records lag. Route the\n"
                + "disagreement to a reviewer; do not fail the applicant on it.");
    }
}
