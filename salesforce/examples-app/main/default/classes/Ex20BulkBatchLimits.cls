/**
 * EX-20 — The batch limit, and chunking a larger list yourself.
 *
 * The SDK will not split an oversized batch for you. Splitting turns one call a
 * caller intended into several billable calls they did not, so it is a decision
 * the caller makes — and in Apex it is a decision with a second cost, because
 * each batch is one of the transaction's 100 callouts.
 */
@IsTest
private class Ex20BulkBatchLimits {
    @IsTest
    static void refusesOversizedBatchesAndChunksExplicitly() {
        Test.setMock(HttpCalloutMock.class, new ExampleApiMock());

        Test.startTest();

        ExampleOutput.heading('The limit is enforced locally');
        ExampleOutput.field('Constants.MAX_BULK_EINS', Constants.MAX_BULK_EINS);

        ExampleOutput.heading('An empty batch');

        try {
            ExampleApiMock.client().nonprofits.checkBulk(new List<String>());
            Assert.fail('An empty batch should have been rejected.');
        } catch (ValidationException e) {
            ExampleOutput.field('sent', 0);
            ExampleOutput.field('message', e.getMessage());
        }

        ExampleOutput.heading('An over-limit batch');

        List<String> tooMany = new List<String>();

        for (Integer index = 0; index <= Constants.MAX_BULK_EINS; index++) {
            tooMany.add(ExampleFixtures.PUBLIC_CHARITY);
        }

        try {
            ExampleApiMock.client().nonprofits.checkBulk(tooMany);
            Assert.fail('An oversized batch should have been rejected.');
        } catch (ValidationException e) {
            ExampleOutput.field('EINs', tooMany.size());
            ExampleOutput.field('sent', 0);
            ExampleOutput.field('message', e.getMessage());
        }

        Assert.areEqual(0, Limits.getCallouts(), 'Neither refusal spent a callout.');


        ExampleOutput.heading('Chunking a larger list');

        // A real workload would hold hundreds of EINs. Ein.chunk is the
        // explicit alternative to silent splitting, and doing it here means the
        // caller can see how many billable requests they are about to make.
        List<String> everything = new List<String>();

        for (Integer index = 0; index < 6; index++) {
            everything.add(ExampleFixtures.PUBLIC_CHARITY);
            everything.add(ExampleFixtures.PUBLIC_CHARITY_SECOND);
            everything.add(ExampleFixtures.PRIVATE_FOUNDATION);
        }

        List<List<String>> batches = Ein.chunk(everything);
        Integer matched = 0;

        for (List<String> batch : batches) {
            BulkCheckResult result = ExampleApiMock.client().nonprofits.checkBulk(batch);
            matched += result.organizations.size();
        }

        // Read inside the block: Test.stopTest() restores the limits the
        // enclosing context had, so a count taken after it measures nothing.
        Integer calloutsUsed = Limits.getCallouts();
        Integer calloutLimit = Limits.getLimitCallouts();

        Test.stopTest();

        ExampleOutput.field('EINs', everything.size());
        ExampleOutput.field('batches', batches.size());
        ExampleOutput.field('organizations returned', matched);
        ExampleOutput.field('callouts used', calloutsUsed);
        ExampleOutput.field('callout limit', calloutLimit);

        // Eighteen EINs fit in one batch of 50, and duplicates collapse to the
        // three distinct records.
        Assert.areEqual(1, batches.size());
        Assert.areEqual(3, matched);

        ExampleOutput.note(
            'Ein.chunk splits a list into batches the endpoint will accept. It is a\n' +
            'separate call rather than something checkBulk does for you, because silently\n' +
            'chunking would misreport how much quota a call consumed.\n\n' +
            'Two Apex-specific limits bound the loop above: 100 callouts per transaction,\n' +
            'and 120 seconds of cumulative callout time. At 50 EINs per request that is\n' +
            '5,000 EINs in the best case and far fewer in practice. For volumes beyond a\n' +
            'few thousand, drive checkBulk from Batch Apex with Database.AllowsCallouts\n' +
            'rather than chaining Queueables.\n\n' +
            'Note that duplicates within a chunk are still sent - pass withDedupe(true), or\n' +
            'clean the input, if the list came from somewhere you do not control.'
        );
    }
}
