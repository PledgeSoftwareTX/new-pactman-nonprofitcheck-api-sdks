/**
 * Bulk — one request for a batch, with local validation and result iteration.
 */
@IsTest
private class BulkOverview {
    @IsTest
    static void checksABatchAndIteratesTheResult() {
        Test.setMock(HttpCalloutMock.class, new ExampleApiMock());

        List<String> eins = new List<String>{ '41-1787097', ExampleFixtures.PUBLIC_CHARITY_SECOND };

        ExampleOutput.note(
            'Checking ' + eins.size() + ' EINs (server limit is ' + Constants.MAX_BULK_EINS + ' per request).'
        );

        Test.startTest();
        BulkCheckResult result;

        try {
            result = ExampleApiMock.client().nonprofits.checkBulk(eins);
        } catch (ValidationException e) {
            // Nothing was sent — the whole batch is rejected before the request.
            for (ValidationIssue issue : e.issues) {
                ExampleOutput.bullet('index ' + issue.index + ': ' + issue.message);
            }

            Assert.fail('The batch should have passed local validation.');
        }
        Test.stopTest();

        ExampleOutput.heading('Matched ' + result.organizations.size() + ' organizations');

        for (Nonprofit organization : result.organizations) {
            Pub78Source pub78 = Sources.getPub78(organization);

            ExampleOutput.bullet(
                organization.ein + '  ' + organization.organization_name + '  pub78_listed=' +
                    (pub78 == null ? 'n/a' : String.valueOf(pub78.verified))
            );
        }

        // EINs with no record come back on a successful response, not as an error.
        if (!result.notFoundEins.isEmpty()) {
            ExampleOutput.field('No record for', String.join(result.notFoundEins, ', '));
        }

        ExampleOutput.field('Checks consumed', result.checkCount);

        Assert.areEqual(2, result.organizations.size());
        Assert.areEqual(0, result.notFoundEins.size());

        // Duplicates are sent as supplied, because each one consumes quota. Pass
        // new RequestOptions().withDedupe(true) to collapse them first.
    }
}
