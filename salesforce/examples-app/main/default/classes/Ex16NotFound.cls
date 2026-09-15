/**
 * EX-16 — A well-formed EIN with no record.
 *
 * "Shaped like an EIN" and "an EIN the IRS has a record for" are different
 * questions. The first is answered locally; only the second costs a callout, and
 * a miss is an ordinary outcome rather than a fault.
 */
@IsTest
private class Ex16NotFound {
    @IsTest
    static void reportsAMissAsNotFound() {
        Test.setMock(HttpCalloutMock.class, new ExampleApiMock());

        String ein = ExampleFixtures.NO_RECORD;

        ExampleOutput.heading('Locally, this EIN is fine');
        ExampleOutput.field('Ein.isValid', Ein.isValid(ein));
        ExampleOutput.field('Ein.normalize', Ein.normalize(ein));

        Assert.isTrue(Ein.isValid(ein));

        Test.startTest();

        ExampleOutput.heading('The API has no record for it');

        try {
            ExampleApiMock.client().nonprofits.check(ein);
            Assert.fail('Expected the lookup to report no record.');
        } catch (NotFoundException e) {
            ExampleOutput.field('exception', 'NotFoundException');
            ExampleOutput.field('category', Errors.wireValue(e.category));
            ExampleOutput.field('origin', Errors.wireValue(e.origin));
            ExampleOutput.field('status', e.status);
            ExampleOutput.field('message', e.getMessage());
            ExampleOutput.field('requestId', e.requestId);
            ExampleOutput.field('attempts', e.attempts);

            Assert.areEqual(404, e.status);
            Assert.areEqual(ErrorCategory.NOT_FOUND, e.category);
            Assert.areEqual(ErrorOrigin.API, e.origin);
            Assert.areEqual(
                1,
                e.attempts,
                'A 404 is never retried: the answer will not change on a second attempt.'
            );

            ExampleOutput.heading('The same failure, rendered for a log');

            Map<String, Object> logged = Errors.toMap(e);

            for (String key : logged.keySet()) {
                ExampleOutput.field(key, logged.get(key));
            }

            Assert.areEqual('not_found', logged.get('category'));
        }

        Test.stopTest();

        ExampleOutput.note(
            'A single check with no record is an HTTP 404, and the SDK raises it as\n' +
            'NotFoundException - which is never retried, because the answer will not change\n' +
            'on a second attempt.\n\n' +
            'Bulk behaves differently on purpose: a batch where some EINs matched is a 200,\n' +
            'with the misses in notFoundEins. See ex-19.\n\n' +
            'No record is not evidence that an organization does not exist. It is the\n' +
            'absence of a record in the extracts behind this API.'
        );
    }
}
