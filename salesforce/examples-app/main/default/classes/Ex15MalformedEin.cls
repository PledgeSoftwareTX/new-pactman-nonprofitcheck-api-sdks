/**
 * EX-15 — A malformed EIN never reaches the API.
 *
 * Local validation is not a convenience. Every request is billable, and in Apex
 * every request also spends one of the transaction's 100 callouts and part of
 * its 120-second cumulative callout budget. A request that cannot succeed should
 * not be one of them.
 *
 * The mock counts what it was asked for, which is how this example proves a
 * negative: nothing was sent.
 */
@IsTest
private class Ex15MalformedEin {
    @IsTest
    static void rejectsLocallyWithoutACallout() {
        ExampleApiMock api = new ExampleApiMock();
        Test.setMock(HttpCalloutMock.class, api);

        Test.startTest();

        ExampleOutput.heading('A single malformed EIN');

        try {
            ExampleApiMock.client().nonprofits.check('4117870');
            Assert.fail('The malformed EIN should have been rejected.');
        } catch (ValidationException e) {
            ExampleOutput.field('exception', 'ValidationException');
            ExampleOutput.field('category', Errors.wireValue(e.category));
            ExampleOutput.field('origin', Errors.wireValue(e.origin));
            ExampleOutput.field('message', e.getMessage());
            ExampleOutput.field('callouts made', api.requests);

            Assert.areEqual(ErrorCategory.VALIDATION, e.category);
            Assert.areEqual(ErrorOrigin.LOCAL, e.origin);
        }

        ExampleOutput.heading('A batch with two bad rows');

        try {
            ExampleApiMock.client()
                .nonprofits.checkBulk(
                    new List<String>{ '411787097', 'nope', '996589560', '1234' }
                );
            Assert.fail('The batch should have been rejected.');
        } catch (ValidationException e) {
            ExampleOutput.field('message', e.getMessage());
            System.debug('');

            for (ValidationIssue issue : e.issues) {
                ExampleOutput.bullet(
                    'index ' + issue.index + ' (' + issue.value + '): ' + issue.message
                );
                Assert.isNotNull(issue.index, 'A batch issue should name the row it came from.');
            }

            Assert.areEqual(2, e.issues.size());
        }

        ExampleOutput.heading('An empty batch');

        try {
            ExampleApiMock.client().nonprofits.checkBulk(new List<String>());
            Assert.fail('An empty batch should have been rejected.');
        } catch (ValidationException e) {
            ExampleOutput.field('message', e.getMessage());
        }

        ExampleOutput.heading('Nothing was sent');
        ExampleOutput.field('callouts made', api.requests);
        ExampleOutput.field('Limits.getCallouts()', Limits.getCallouts());

        Test.stopTest();

        Assert.areEqual(
            0,
            api.requests,
            'A locally rejected EIN must not reach the API, or cost a callout.'
        );

        ExampleOutput.note(
            'origin is what separates these from an API-side rejection. A\n' +
            'ValidationException with origin LOCAL means nothing was sent and nothing was\n' +
            'billed; a BadRequestException with origin API means the API looked at the\n' +
            'request and refused it. Retrying the first is pointless until the input\n' +
            'changes, which is why this SDK never retries either.\n\n' +
            'Errors.toMap(e) renders any of them for a structured log, and never contains\n' +
            'the API key - which in Apex is trivially true, because Apex cannot read it.'
        );
    }
}
