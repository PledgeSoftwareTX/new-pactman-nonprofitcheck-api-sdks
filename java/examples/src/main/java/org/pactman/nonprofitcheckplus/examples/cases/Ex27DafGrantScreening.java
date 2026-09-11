package org.pactman.nonprofitcheckplus.examples.cases;

import java.util.Arrays;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import org.pactman.nonprofitcheckplus.Sources;
import org.pactman.nonprofitcheckplus.devtools.FixtureEins;
import org.pactman.nonprofitcheckplus.examples.support.Example;
import org.pactman.nonprofitcheckplus.examples.support.ExampleContext;
import org.pactman.nonprofitcheckplus.examples.support.Output;
import org.pactman.nonprofitcheckplus.examples.support.Screening;
import org.pactman.nonprofitcheckplus.models.BmfSource;
import org.pactman.nonprofitcheckplus.models.BulkCheckResult;
import org.pactman.nonprofitcheckplus.models.Nonprofit;

/**
 * EX-27 — Donor-advised fund grant screening.
 *
 * <p>A DAF has obligations a donation platform does not. A grant to a private
 * foundation triggers expenditure responsibility; an OFAC finding stops the
 * grant outright; and "the API returned no OFAC data" is not a clean screen.
 *
 * <p>Same API responses as ex-26, stricter policy. Both are correct.
 */
public final class Ex27DafGrantScreening implements Example {

    @Override
    public String id() {
        return "ex-27";
    }

    @Override
    public String title() {
        return "DAF grant screening: a stricter policy on the same evidence";
    }

    @Override
    public void run(String[] args) {
        List<String> candidates = Arrays.asList(
                FixtureEins.PUBLIC_CHARITY,
                FixtureEins.PRIVATE_FOUNDATION,
                FixtureEins.OFAC_MATCH,
                FixtureEins.OFAC_UNAVAILABLE,
                FixtureEins.CONFLICTED);

        try (ExampleContext context = ExampleContext.withFixtures()) {
            BulkCheckResult result = context.client().nonprofits().checkBulk(candidates);

            Map<String, Nonprofit> byEin = new LinkedHashMap<>();

            for (Nonprofit organization : result.getOrganizations()) {
                byEin.put(organization.getEin(), organization);
            }

            for (String ein : candidates) {
                Nonprofit nonprofit = byEin.get(ein);

                if (nonprofit == null) {
                    Output.heading(ein + " — no record");
                    Output.field("decision", "HOLD — no record to screen against");
                    continue;
                }

                Output.heading(nonprofit.getOrganizationName() + " (" + ein + ")");

                Screening.OfacState ofac = Screening.ofacState(nonprofit);
                BmfSource bmf = Sources.bmf(nonprofit);
                boolean privateFoundation = bmf != null
                        && bmf.getSubsectionDescription() != null
                        && bmf.getSubsectionDescription().toLowerCase(java.util.Locale.ROOT)
                                .contains("private foundation");

                Output.field("ofac", ofac);
                Output.field("pub78_verified", nonprofit.getPub78Verified());
                Output.field("classification", bmf == null ? null : bmf.getSubsectionDescription());
                Output.field("bmf/pub78 conflict", nonprofit.getIrsBmfPub78Conflict());

                // The DAF's policy. Anything other than an affirmative OFAC
                // no-match stops the grant, because an unscreened grant and a
                // screened one are not the same thing.
                String decision;

                if (ofac != Screening.OfacState.NO_MATCH) {
                    decision = "STOP — OFAC screening did not return an affirmative no-match";
                } else if (!Boolean.TRUE.equals(nonprofit.getPub78Verified())) {
                    decision = "STOP — not listed in Publication 78";
                } else if (Boolean.TRUE.equals(nonprofit.getIrsBmfPub78Conflict())) {
                    decision = "HOLD — the IRS sources disagree";
                } else if (privateFoundation) {
                    decision = "HOLD — expenditure responsibility applies to a private foundation";
                } else {
                    decision = "PROCEED under this fund's policy";
                }

                Output.field("decision", decision);
            }
        }

        Output.note("Two organizations here have no OFAC match. One of them returned the field\n"
                + "with no value, and this fund stops on it — because \"we did not screen\" and\n"
                + "\"we screened and found nothing\" are different sentences to write in a file\n"
                + "that a regulator may later read.\n\n"
                + "Compare with ex-26: a donation platform reading these same responses\n"
                + "reasonably proceeds where this fund holds.");
    }
}
