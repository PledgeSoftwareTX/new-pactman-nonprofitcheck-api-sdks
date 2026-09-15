/**
 * EX-29 — Re-checking immediately before money moves.
 *
 * A verification done at onboarding is a statement about the day it ran. The
 * check that matters for a disbursement is the one taken at disbursement time —
 * and it has to fail closed, because a payment released on a failed check is a
 * payment nobody screened.
 */
@IsTest
private class Ex29PreDisbursementRecheck {
    /**
     * How long a screening result is allowed to stand before a payment. The
     * other SDKs use the same 120 days; it is a threshold, not a fact about the
     * data.
     */
    private static final Integer MAX_RESULT_AGE_DAYS = 120;

    @IsTest
    static void failsClosedWhenTheRecheckDoesNotComplete() {
        Test.setMock(HttpCalloutMock.class, new ExampleApiMock());

        Map<String, String> decisions = new Map<String, String>();

        Test.startTest();

        for (
            String ein : new List<String>{
                ExampleFixtures.PUBLIC_CHARITY,
                ExampleFixtures.REVOKED,
                ExampleFixtures.STALE_DATA,
                ExampleFixtures.CONTROL_SLOW
            }
        ) {
            ExampleOutput.heading('Disbursement check for ' + ein);

            Nonprofit nonprofit;

            try {
                // A payment gate is latency-sensitive and the answer is needed
                // now, so the budget is short. Failing fast is the point: the
                // fallback is "do not pay yet", which is safe.
                nonprofit = ExampleApiMock.client()
                    .nonprofits.check(ein, new RequestOptions().withTimeoutMs(5000))
                    .nonprofit;
            } catch (PactmanException failure) {
                // Fail closed. The screen did not happen, so the payment does
                // not either.
                ExampleOutput.field('category', Errors.wireValue(failure.category));
                ExampleOutput.field('message', failure.getMessage());
                ExampleOutput.field('decision', 'HOLD - the re-check did not complete');
                decisions.put(ein, 'HOLD');
                continue;
            }

            if (nonprofit == null) {
                ExampleOutput.field('decision', 'HOLD - no record returned');
                decisions.put(ein, 'HOLD');
                continue;
            }

            List<String> findings = ExampleScreening.findings(nonprofit);
            Integer age = ExampleScreening.oldestSourceAgeDays(nonprofit);

            ExampleOutput.field('organization', nonprofit.organization_name);
            ExampleOutput.field('oldest source', age == null ? null : age + ' days');

            for (String finding : findings) {
                ExampleOutput.bullet(finding);
            }

            String decision;
            String outcome;

            if (!findings.isEmpty()) {
                outcome = 'HOLD';
                decision = 'HOLD - the re-check surfaced findings';
            } else if (age != null && age > MAX_RESULT_AGE_DAYS) {
                outcome = 'HOLD';
                decision = 'HOLD - the underlying data is older than this gate allows';
            } else {
                outcome = 'RELEASE';
                decision = 'RELEASE under this gate\'s policy';
            }

            decisions.put(ein, outcome);
            ExampleOutput.field('decision', decision);
        }

        Test.stopTest();

        ExampleOutput.heading('Gate summary');

        Integer held = 0;

        for (String ein : decisions.keySet()) {
            if (decisions.get(ein) == 'HOLD') {
                held++;
            }
        }

        ExampleOutput.field('held', held);
        ExampleOutput.field('released', decisions.size() - held);

        // Three holds, for three different reasons.
        Assert.areEqual(
            'RELEASE',
            decisions.get(ExampleFixtures.PUBLIC_CHARITY),
            'Clean and current.'
        );
        Assert.areEqual(
            'HOLD',
            decisions.get(ExampleFixtures.REVOKED),
            'The re-check surfaced findings.'
        );
        Assert.areEqual(
            'HOLD',
            decisions.get(ExampleFixtures.STALE_DATA),
            'Nothing adverse, but older than this gate relies on.'
        );
        Assert.areEqual(
            'HOLD',
            decisions.get(ExampleFixtures.CONTROL_SLOW),
            'The call did not complete, so nothing was screened.'
        );
        Assert.areEqual(3, held);

        ExampleOutput.note(
            'Three of the four hold, for three different reasons: a finding, stale source\n' +
            'data, and a call that did not complete in time. Only the last one is about the\n' +
            'SDK, and it is the one worth being deliberate about - an exception handler\n' +
            'that logs and continues would release a payment on the strength of a check\n' +
            'that never ran.\n\n' +
            'Catching PactmanException rather than a specific subclass is deliberate here.\n' +
            'A payment gate does not care which way the check failed; it cares that it\n' +
            'failed.\n\n' +
            'The stale-data hold is not a fault in the record. Nothing on it is adverse; it\n' +
            'is simply older than this gate is willing to rely on, and that is a threshold\n' +
            'you own.'
        );
    }
}
