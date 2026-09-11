package org.pactman.nonprofitcheckplus.examples.cases;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import org.pactman.nonprofitcheckplus.Endpoints;
import org.pactman.nonprofitcheckplus.config.PactmanClientOptions;
import org.pactman.nonprofitcheckplus.devtools.FixtureEins;
import org.pactman.nonprofitcheckplus.examples.support.Example;
import org.pactman.nonprofitcheckplus.examples.support.ExampleContext;
import org.pactman.nonprofitcheckplus.examples.support.Output;
import org.pactman.nonprofitcheckplus.examples.support.Screening;
import org.pactman.nonprofitcheckplus.models.BulkCheckResult;
import org.pactman.nonprofitcheckplus.models.Nonprofit;

/**
 * EX-30 — Re-verifying a whole portfolio.
 *
 * <p>A periodic sweep over every organization you have a relationship with. The
 * output is a work queue, not a set of decisions: what changed, what is now
 * questionable, and what could not be checked.
 */
public final class Ex30PortfolioReverification implements Example {

    @Override
    public String id() {
        return "ex-30";
    }

    @Override
    public String title() {
        return "A scheduled sweep that produces a work queue";
    }

    @Override
    public void run(String[] args) {
        // The portfolio, and what the last sweep concluded about each row.
        Map<String, String> lastKnown = new LinkedHashMap<>();
        lastKnown.put(FixtureEins.PUBLIC_CHARITY, "clear");
        lastKnown.put(FixtureEins.PUBLIC_CHARITY_SECOND, "clear");
        lastKnown.put(FixtureEins.REVOKED, "clear");
        lastKnown.put(FixtureEins.OFAC_MATCH, "clear");
        lastKnown.put(FixtureEins.REINSTATED, "findings");
        lastKnown.put(FixtureEins.STALE_DATA, "clear");
        lastKnown.put(FixtureEins.NO_RECORD, "clear");

        List<String> portfolio = new ArrayList<>(lastKnown.keySet());

        // A courtesy ceiling: a sweep is background work and should not spend
        // the rate limit a customer-facing path needs.
        try (ExampleContext context = ExampleContext.withFixtures(
                PactmanClientOptions.builder().maxRequestsPerSecond(5))) {

            List<String> changed = new ArrayList<>();
            List<String> unverifiable = new ArrayList<>();
            int checked = 0;

            // One bulk request per batch, rather than a request per row.
            for (int start = 0; start < portfolio.size(); start += Endpoints.MAX_BULK_EINS) {
                List<String> chunk = portfolio.subList(
                        start, Math.min(start + Endpoints.MAX_BULK_EINS, portfolio.size()));
                BulkCheckResult result = context.client().nonprofits().checkBulk(chunk);

                Map<String, Nonprofit> byEin = new LinkedHashMap<>();

                for (Nonprofit organization : result.getOrganizations()) {
                    byEin.put(organization.getEin(), organization);
                }

                for (String ein : chunk) {
                    Nonprofit nonprofit = byEin.get(ein);

                    if (nonprofit == null) {
                        unverifiable.add(ein);
                        continue;
                    }

                    checked += 1;
                    List<String> findings = Screening.findings(nonprofit);
                    String now = findings.isEmpty() ? "clear" : "findings";

                    Output.heading(nonprofit.getOrganizationName() + " (" + ein + ")");
                    Output.field("last sweep", lastKnown.get(ein));
                    Output.field("this sweep", now);

                    for (String finding : findings) {
                        Output.bullet(finding);
                    }

                    if (!now.equals(lastKnown.get(ein))) {
                        changed.add(ein);
                        Output.field("queue", "CHANGED — needs a look");
                    }
                }
            }

            Output.heading("Sweep summary");
            Output.field("portfolio", portfolio.size());
            Output.field("checked", checked);
            Output.field("changed since last sweep", changed);
            Output.field("could not be verified", unverifiable);
        }

        Output.note("Two rows changed in opposite directions: one picked up findings and one\n"
                + "cleared them. A sweep that only reported new problems would miss the second,\n"
                + "and someone would keep treating a resolved flag as live.\n\n"
                + "The EIN with no record is neither clear nor a finding — it is unverifiable,\n"
                + "and it belongs in its own bucket. Folding it into either of the other two\n"
                + "reports something the API never said.");
    }
}
