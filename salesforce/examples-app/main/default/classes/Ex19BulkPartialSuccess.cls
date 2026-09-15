/**
 * EX-19 — Partial success in a batch.
 *
 * A batch where some EINs matched is a successful response with the misses listed
 * inside it — not an exception. Code wrapped in a try/catch that only handles
 * the happy path will process the matches and never notice the rest.
 */
@IsTest
private class Ex19BulkPartialSuccess {
    @IsTest
    static void reportsMissesInsideASuccessfulResponse() {
        Test.setMock(HttpCalloutMock.class, new ExampleApiMock());

        List<String> eins = new List<String>{
            ExampleFixtures.PUBLIC_CHARITY,
            ExampleFixtures.NO_RECORD,
            ExampleFixtures.PUBLIC_CHARITY_SECOND
        };

        // No try/catch here on purpose: a miss is not an exception.
        Test.startTest();
        BulkCheckResult result = ExampleApiMock.client().nonprofits.checkBulk(eins);
        Test.stopTest();

        ExampleOutput.heading('The response');
        ExampleOutput.field('HTTP status', result.status);
        ExampleOutput.field('organizations', result.organizations.size());
        ExampleOutput.field('notFoundEins', result.notFoundEins);
        ExampleOutput.field('errors', result.errors.size());
        ExampleOutput.field('checkCount', result.checkCount);

        Assert.areEqual(200, result.status, 'Partial success is an HTTP 200.');
        Assert.areEqual(2, result.organizations.size());
        Assert.areEqual(1, result.notFoundEins.size());
        Assert.areEqual(ExampleFixtures.NO_RECORD, result.notFoundEins[0]);

        ExampleOutput.heading('What the errors list carried');

        for (ApiErrorDetail detail : result.errors) {
            ExampleOutput.field('resource', detail.resource);
            ExampleOutput.field('code', detail.code);
            ExampleOutput.field('reason', detail.reason);
            ExampleOutput.field('eins', detail.eins);
        }

        Assert.areEqual(1, result.errors.size(), 'The miss is reported in the envelope.');

        ExampleOutput.heading('Matched');

        for (Nonprofit organization : result.organizations) {
            ExampleOutput.bullet(organization.ein + ' - ' + organization.organization_name);
        }

        // Reconciling every input against the response is the habit that
        // catches the row nobody looked at.
        ExampleOutput.heading('Reconciling against the input');

        Map<String, Nonprofit> byEin = result.byEin();

        for (String ein : eins) {
            ExampleOutput.field(ein, byEin.containsKey(ein) ? 'matched' : 'no record');
        }

        Assert.areEqual(
            eins.size(),
            byEin.size() + result.notFoundEins.size(),
            'Every input should be accounted for as either matched or missing.'
        );

        ExampleOutput.note(
            'Three EINs, two records, one 200. notFoundEins is collected from the\n' +
            'envelope\'s errors list, so the misses are as visible as the matches - but only\n' +
            'if you read them.\n\n' +
            'Only matched EINs are billed, which is why checkCount rose by two and not by\n' +
            'three - and why usage cannot be reconstructed from the size of the batch you\n' +
            'sent. See ex-21.'
        );
    }
}
