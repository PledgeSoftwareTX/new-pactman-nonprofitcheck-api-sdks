package org.pactman.nonprofitcheckplus.examples.cases;

import org.pactman.nonprofitcheckplus.devtools.FixtureEins;
import org.pactman.nonprofitcheckplus.devtools.ApiDate;
import org.pactman.nonprofitcheckplus.examples.support.Example;
import org.pactman.nonprofitcheckplus.examples.support.ExampleContext;
import org.pactman.nonprofitcheckplus.examples.support.Output;
import org.pactman.nonprofitcheckplus.examples.support.Screening;
import org.pactman.nonprofitcheckplus.models.Nonprofit;

/**
 * EX-14 — How fresh the underlying data is.
 *
 * <p>Every finding on a record is as old as the extract it came from. A clean
 * result from a two-year-old extract is a clean result about two years ago,
 * which is a different statement from the one most workflows think they are
 * making.
 */
public final class Ex14DataFreshness implements Example {

    /** A re-review threshold. Yours belongs in your policy, not in the SDK. */
    private static final long STALE_AFTER_DAYS = 180;

    @Override
    public String id() {
        return "ex-14";
    }

    @Override
    public String title() {
        return "Reading how old the findings are";
    }

    @Override
    public void run(String[] args) {
        try (ExampleContext context = ExampleContext.withFixtures()) {
            for (String ein : new String[] {FixtureEins.PUBLIC_CHARITY, FixtureEins.STALE_DATA}) {
                Nonprofit nonprofit = context.client().nonprofits().check(ein).getNonprofit();

                Output.heading(nonprofit.getOrganizationName() + " (" + ein + ")");

                for (String[] source : new String[][] {
                    {"most_recent_bmf", nonprofit.getMostRecentBmf()},
                    {"most_recent_pub78", nonprofit.getMostRecentPub78()},
                    {"organization_info_last_modified",
                            nonprofit.getOrganizationInfoLastModified()},
                    {"report_date", nonprofit.getReportDate()},
                }) {
                    Long age = ApiDate.ageInDays(source[1]);
                    Output.field(
                            source[0],
                            source[1] + (age == null ? "" : "  (" + age + " days ago)"));
                }

                Long oldest = Screening.oldestSourceAgeDays(nonprofit);

                System.out.println();
                Output.field("oldest source", oldest == null ? null : oldest + " days");
                Output.field(
                        "past a " + STALE_AFTER_DAYS + "-day rule",
                        oldest != null && oldest > STALE_AFTER_DAYS);
            }
        }

        Output.note("The second organization has nothing adverse on its record and every source\n"
                + "is well over a year old. Both facts are true, and a workflow that reads only\n"
                + "the first has re-verified nothing.\n\n"
                + "The API formats dates for display, not for machines. Parsing them means\n"
                + "assuming a locale and a time zone, which is why the SDK hands them back as\n"
                + "strings and leaves the assumption to code like this, where it is visible.");
    }
}
