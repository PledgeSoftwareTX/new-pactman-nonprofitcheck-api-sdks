package org.pactman.nonprofitcheckplus.examples.cases;

import java.util.List;
import org.pactman.nonprofitcheckplus.config.PactmanClientOptions;
import org.pactman.nonprofitcheckplus.config.RequestOptions;
import org.pactman.nonprofitcheckplus.devtools.FixtureEins;
import org.pactman.nonprofitcheckplus.examples.support.Example;
import org.pactman.nonprofitcheckplus.examples.support.ExampleContext;
import org.pactman.nonprofitcheckplus.examples.support.Output;
import org.pactman.nonprofitcheckplus.examples.support.Screening;
import org.pactman.nonprofitcheckplus.exceptions.PactmanException;
import org.pactman.nonprofitcheckplus.models.Nonprofit;

/**
 * EX-29 — Re-checking immediately before money moves.
 *
 * <p>A verification done at onboarding is a statement about the day it ran. The
 * check that matters for a disbursement is the one taken at disbursement time —
 * and it has to fail closed, because a payment released on a failed check is a
 * payment nobody screened.
 */
public final class Ex29PreDisbursementRecheck implements Example {

    /** How long a screening result is allowed to stand before a payment. */
    private static final long MAX_RESULT_AGE_DAYS = 30;

    @Override
    public String id() {
        return "ex-29";
    }

    @Override
    public String title() {
        return "A pre-disbursement re-check that fails closed";
    }

    @Override
    public void run(String[] args) {
        // A payment gate is latency-sensitive and the answer is needed now, so
        // the timeout is short and retries are few. Failing fast is the point:
        // the fallback is "do not pay yet", which is safe.
        try (ExampleContext context = ExampleContext.withFixtures(
                PactmanClientOptions.builder()
                        .timeoutMs(5_000)
                        .retry(ExampleContext.quickRetries(1)))) {

            for (String ein : new String[] {
                FixtureEins.PUBLIC_CHARITY,
                FixtureEins.REVOKED,
                FixtureEins.STALE_DATA,
                FixtureEins.CONTROL_SLOW,
            }) {
                Output.heading("Disbursement check for " + ein);

                Nonprofit nonprofit;

                try {
                    nonprofit = context.client()
                            .nonprofits()
                            // A tight per-request budget: this call sits in the
                            // path of a payment.
                            .check(ein, new RequestOptions().timeoutMs(700))
                            .getNonprofit();
                } catch (PactmanException failure) {
                    // Fail closed. The screen did not happen, so the payment
                    // does not either.
                    Output.field("exception", failure.getClass().getSimpleName());
                    Output.field("category", failure.category());
                    Output.field("decision", "HOLD — the re-check did not complete");
                    continue;
                }

                if (nonprofit == null) {
                    Output.field("decision", "HOLD — no record returned");
                    continue;
                }

                List<String> findings = Screening.findings(nonprofit);
                Long age = Screening.oldestSourceAgeDays(nonprofit);

                Output.field("organization", nonprofit.getOrganizationName());
                Output.field("oldest source", age == null ? null : age + " days");

                for (String finding : findings) {
                    Output.bullet(finding);
                }

                String decision;

                if (!findings.isEmpty()) {
                    decision = "HOLD — the re-check surfaced findings";
                } else if (age != null && age > MAX_RESULT_AGE_DAYS) {
                    decision = "HOLD — the underlying data is older than this gate allows";
                } else {
                    decision = "RELEASE under this gate's policy";
                }

                Output.field("decision", decision);
            }
        }

        Output.note("Three of the four hold, for three different reasons: a finding, stale\n"
                + "source data, and a call that did not complete in time. Only the last one is\n"
                + "about the SDK, and it is the one worth being deliberate about — an exception\n"
                + "handler that logs and continues would release a payment on the strength of a\n"
                + "check that never ran.\n\n"
                + "The stale-data hold is not a fault in the record. Nothing on it is adverse;\n"
                + "it is simply older than this gate is willing to rely on, and that is a\n"
                + "threshold you own.");
    }
}
