/**
 * EX-21 — Usage tracking.
 *
 * `checkCount` is a running total for the billing cycle, not the size of the
 * request that returned it. Reading it as a per-request cost is the single most
 * common way to misreport usage.
 */
@IsTest
private class Ex21UsageTracking {
    @IsTest
    static void readsCheckCountAsACumulativeTotal() {
        Test.setMock(HttpCalloutMock.class, new ExampleApiMock());

        Test.startTest();
        SingleCheckResult first = ExampleApiMock.client()
            .nonprofits.check(ExampleFixtures.PUBLIC_CHARITY);

        BulkCheckResult batch = ExampleApiMock.client()
            .nonprofits.checkBulk(
                new List<String>{
                    ExampleFixtures.PUBLIC_CHARITY,
                    ExampleFixtures.PUBLIC_CHARITY_SECOND,
                    ExampleFixtures.PRIVATE_FOUNDATION,
                    ExampleFixtures.NO_RECORD
                }
            );
        Test.stopTest();

        ExampleOutput.heading('A single check');
        ExampleOutput.field('checkCount', first.checkCount);
        ExampleOutput.field('timeTakenMs', first.timeTakenMs);

        ExampleOutput.heading('A batch of four, one of which has no record');
        ExampleOutput.field('EINs sent', 4);
        ExampleOutput.field('organizations returned', batch.organizations.size());
        ExampleOutput.field('notFoundEins', batch.notFoundEins);
        ExampleOutput.field('checkCount', batch.checkCount);

        ExampleOutput.heading('What the batch actually consumed');
        ExampleOutput.field('count before', first.checkCount);
        ExampleOutput.field('count after', batch.checkCount);

        Integer delta = batch.checkCount - first.checkCount;

        ExampleOutput.field('delta', delta);

        Assert.areEqual(1, first.checkCount, 'One check, one unit of quota.');
        Assert.areEqual(
            3,
            delta,
            'Four EINs went out and three were billed: the miss was refunded.'
        );
        Assert.areEqual(3, batch.organizations.size());
        Assert.areEqual(1, batch.notFoundEins.size());

        ExampleOutput.note(
            'Four EINs went out and the counter moved by three, because the EIN with no\n' +
            'record was not billed. Two consequences:\n\n' +
            '  - the size of your batch is not its cost\n' +
            '  - a delta between two responses is, and it is the only number that is\n\n' +
            'The counter resets when a new billing cycle begins, so a delta across that\n' +
            'boundary is meaningless. Read the value the API reports rather than keeping\n' +
            'your own running total.'
        );
    }
}
