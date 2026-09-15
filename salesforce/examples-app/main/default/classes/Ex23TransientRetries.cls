/**
 * EX-23 — What gets retried, and what never does.
 *
 * The other Pactman SDKs retry transient 5xx with jittered backoff. Apex cannot
 * sleep, so this SDK retries exactly one thing: a `GET` that produced no
 * response at all, once, immediately.
 *
 * Everything else is surfaced. A `POST` is never retried, because the bulk
 * endpoint bills per EIN and a request that was received but whose response was
 * lost would be charged twice.
 */
@IsTest
private class Ex23TransientRetries {
    /** Fails every callout with a lost response, and counts the attempts. */
    private class LostResponseMock implements HttpCalloutMock {
        public Integer attempts = 0;

        public HttpResponse respond(HttpRequest request) {
            attempts++;

            throw new CalloutException('Unable to tunnel through proxy');
        }
    }

    @IsTest
    static void retriesALostGetOnceAndNeverAPost() {
        ExampleOutput.heading('A GET with no response is retried once');

        LostResponseMock lostGet = new LostResponseMock();
        Test.setMock(HttpCalloutMock.class, lostGet);

        Test.startTest();

        try {
            ExampleApiMock.client().nonprofits.check(ExampleFixtures.PUBLIC_CHARITY);
            Assert.fail('Expected the callout to produce no response.');
        } catch (NetworkException e) {
            ExampleOutput.field('exception', 'NetworkException');
            ExampleOutput.field('category', Errors.wireValue(e.category));
            ExampleOutput.field('origin', Errors.wireValue(e.origin));
            ExampleOutput.field('attempts', e.attempts);
            ExampleOutput.field('callouts made', lostGet.attempts);

            Assert.areEqual(ErrorCategory.NETWORK, e.category);
            Assert.areEqual(ErrorOrigin.LOCAL, e.origin);
            Assert.areEqual(2, e.attempts, 'One attempt, then one immediate retry.');
            Assert.areEqual(2, lostGet.attempts);
        }

        ExampleOutput.heading('A POST is never retried');

        LostResponseMock lostPost = new LostResponseMock();
        Test.setMock(HttpCalloutMock.class, lostPost);

        try {
            ExampleApiMock.client()
                .nonprofits.checkBulk(new List<String>{ ExampleFixtures.PUBLIC_CHARITY });
            Assert.fail('Expected the callout to produce no response.');
        } catch (NetworkException e) {
            ExampleOutput.field('attempts', e.attempts);
            ExampleOutput.field('callouts made', lostPost.attempts);

            Assert.areEqual(
                1,
                e.attempts,
                'The bulk endpoint bills per EIN; a lost response must not be charged twice.'
            );
            Assert.areEqual(1, lostPost.attempts);
        }

        ExampleOutput.heading('An HTTP error is never retried');

        ExampleApiMock api = new ExampleApiMock();
        Test.setMock(HttpCalloutMock.class, api);

        try {
            ExampleApiMock.client().nonprofits.check(ExampleFixtures.CONTROL_RATE_LIMITED);
            Assert.fail('Expected a rate limit.');
        } catch (RateLimitException e) {
            ExampleOutput.field('status', e.status);
            ExampleOutput.field('attempts', e.attempts);
            ExampleOutput.field('callouts made', api.requests);

            Assert.areEqual(1, e.attempts);
            Assert.areEqual(1, api.requests);
        }

        Test.stopTest();

        ExampleOutput.note(
            'Retried: a GET that produced no HTTP response, once, immediately.\n' +
            'Never retried: a POST, a timeout, and every HTTP status including 429 and 503.\n\n' +
            'The reasons are quota and the transaction. A POST that was received but whose\n' +
            'response was lost has already been billed. A timeout has already spent its\n' +
            'share of the 120-second cumulative callout budget. And an HTTP error cannot be\n' +
            'waited out without sleep.\n\n' +
            'What you get instead is Retry-After on the exception and CheckQueueable to\n' +
            'act on it. That is a real, working backoff - it is just asynchronous, which\n' +
            'is the only kind Apex has.'
        );
    }
}
