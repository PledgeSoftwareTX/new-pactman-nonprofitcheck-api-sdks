/**
 * EX-30 — Re-verifying a whole portfolio.
 *
 * A periodic sweep over every organization you have a relationship with. The
 * output is a work queue, not a set of decisions: what changed, what is now
 * questionable, and what could not be checked.
 *
 * In Apex a sweep has a shape the other SDKs do not have to think about. One
 * transaction gets 100 callouts and 120 seconds of cumulative callout time, so
 * beyond a few thousand EINs this belongs in Batch Apex with
 * `Database.AllowsCallouts` rather than in a chain of Queueables.
 */
@IsTest
private class Ex30PortfolioReverification {
    @IsTest
    static void producesAWorkQueueOfWhatChanged() {
        Test.setMock(HttpCalloutMock.class, new ExampleApiMock());

        // The portfolio, and what the last sweep concluded about each row.
        Map<String, String> lastSweep = new Map<String, String>{
            ExampleFixtures.PUBLIC_CHARITY => 'clear',
            // Flagged by the last sweep. Whatever the finding was, it is gone
            // now - which is a change this sweep has to report just as loudly
            // as a new one.
            ExampleFixtures.PUBLIC_CHARITY_SECOND => 'findings',
            ExampleFixtures.REVOKED => 'clear',
            ExampleFixtures.OFAC_MATCH => 'clear',
            ExampleFixtures.REINSTATED => 'findings',
            ExampleFixtures.STALE_DATA => 'clear',
            ExampleFixtures.NO_RECORD => 'clear'
        };

        List<String> portfolio = new List<String>(lastSweep.keySet());
        List<String> changed = new List<String>();
        List<String> unverifiable = new List<String>();
        Integer checked = 0;

        Test.startTest();

        // One bulk request per batch, rather than a request per row.
        for (List<String> batch : Ein.chunk(portfolio)) {
            BulkCheckResult result = ExampleApiMock.client().nonprofits.checkBulk(batch);
            Map<String, Nonprofit> byEin = result.byEin();

            for (String ein : batch) {
                Nonprofit nonprofit = byEin.get(ein);

                if (nonprofit == null) {
                    unverifiable.add(ein);
                    continue;
                }

                checked++;

                List<String> findings = ExampleScreening.findings(nonprofit);
                String now = findings.isEmpty() ? 'clear' : 'findings';

                ExampleOutput.heading(nonprofit.organization_name + ' (' + ein + ')');
                ExampleOutput.field('last sweep', lastSweep.get(ein));
                ExampleOutput.field('this sweep', now);

                for (String finding : findings) {
                    ExampleOutput.bullet(finding);
                }

                if (now != lastSweep.get(ein)) {
                    changed.add(ein);
                    ExampleOutput.field('queue', 'CHANGED - needs a look');
                }
            }
        }

        // Read inside the block: Test.stopTest() restores the limits the
        // enclosing context had, so a count taken after it measures nothing.
        Integer calloutsUsed = Limits.getCallouts();
        Integer calloutLimit = Limits.getLimitCallouts();

        Test.stopTest();

        ExampleOutput.heading('Sweep summary');
        ExampleOutput.field('portfolio', portfolio.size());
        ExampleOutput.field('checked', checked);
        ExampleOutput.field('changed since last sweep', changed);
        ExampleOutput.field('could not be verified', unverifiable);
        ExampleOutput.field('callouts used', calloutsUsed);
        ExampleOutput.field('callout limit', calloutLimit);

        Assert.areEqual(6, checked, 'Six of the seven have records.');
        Assert.areEqual(1, unverifiable.size());
        Assert.areEqual(ExampleFixtures.NO_RECORD, unverifiable[0]);
        Assert.areEqual(1, calloutsUsed, 'Seven EINs fit in one batch.');

        // Two rows picked up findings, and one cleared them.
        Assert.areEqual(3, changed.size());
        Assert.isTrue(new Set<String>(changed).contains(ExampleFixtures.REVOKED));
        Assert.isTrue(new Set<String>(changed).contains(ExampleFixtures.OFAC_MATCH));
        Assert.isTrue(
            new Set<String>(changed).contains(ExampleFixtures.PUBLIC_CHARITY_SECOND),
            'A row that cleared is a change too.'
        );

        ExampleOutput.note(
            'Rows changed in both directions: two picked up findings and one cleared them.\n' +
            'A sweep that only reported new problems would miss the third, and someone\n' +
            'would keep treating a resolved flag as live.\n\n' +
            'The EIN with no record is neither clear nor a finding - it is unverifiable,\n' +
            'and it belongs in its own bucket. Folding it into either of the other two\n' +
            'reports something the API never said.\n\n' +
            'Ein.chunk sized the batches here. For a real portfolio, note the callout\n' +
            'figures above: 100 per transaction at 50 EINs each is 5,000 in the best case.\n' +
            'Past that, drive checkBulk from Batch Apex.'
        );
    }
}
