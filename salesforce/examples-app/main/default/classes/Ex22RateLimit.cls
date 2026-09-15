/**
 * EX-22 — Rate limiting.
 *
 * HTTP 429 arrives as a {@link RateLimitException} carrying the server's
 * `Retry-After`.
 *
 * **This is where Apex diverges most from the other SDKs.** They wait the
 * server's interval and try again, and they offer a client-side
 * `maxRequestsPerSecond` ceiling. Both are implemented with sleep, and Apex has
 * no sleep primitive — a busy-wait loop burns the 10-second synchronous CPU
 * limit and takes the transaction down with it. So this SDK does neither, and
 * says so: `Retry-After` is surfaced on the exception, and
 * {@link CheckQueueable} re-enqueues with a delay, which is the only real
 * backoff Apex offers.
 */
@IsTest
private class Ex22RateLimit {
    @IsTest
    static void surfacesRetryAfterRatherThanWaiting() {
        ExampleApiMock api = new ExampleApiMock();
        Test.setMock(HttpCalloutMock.class, api);

        Test.startTest();

        ExampleOutput.heading('A 429, surfaced rather than retried');

        try {
            ExampleApiMock.client().nonprofits.check(ExampleFixtures.CONTROL_RATE_LIMITED);
            Assert.fail('Expected the API to report a rate limit.');
        } catch (RateLimitException e) {
            ExampleOutput.field('exception', 'RateLimitException');
            ExampleOutput.field('category', Errors.wireValue(e.category));
            ExampleOutput.field('status', e.status);
            ExampleOutput.field('retryAfterSeconds', e.retryAfterSeconds);
            ExampleOutput.field('attempts', e.attempts);
            ExampleOutput.field('requestId', e.requestId);

            Assert.areEqual(429, e.status);
            Assert.areEqual(ErrorCategory.RATE_LIMIT, e.category);
            Assert.isNotNull(e.retryAfterSeconds, 'The server sent a Retry-After header.');
            // retryAfterSeconds is a Decimal; compare through intValue() rather
            // than boxing an Integer against it.
            Assert.areEqual(1, e.retryAfterSeconds.intValue(), 'The server sent Retry-After: 1.');
            Assert.areEqual(
                1,
                e.attempts,
                'An HTTP error is never retried in-transaction, whatever the status.'
            );
        }

        Test.stopTest();

        ExampleOutput.field('callouts made', api.requests);
        Assert.areEqual(1, api.requests, 'One attempt, not three.');

        ExampleOutput.heading('Where the backoff actually goes');
        ExampleOutput.bullet(
            'Read retryAfterSeconds off the exception and hand the work to CheckQueueable.'
        );
        ExampleOutput.bullet(
            'It batches at ' + Constants.MAX_BULK_EINS +
                ', chains itself until the list is done, and re-enqueues with a delay ' +
                'when the API rate-limits.'
        );

        ExampleOutput.note(
            'Three things the other Pactman SDKs do that this one deliberately does not:\n\n' +
            '  - retry a 429 in-process after waiting Retry-After\n' +
            '  - apply exponential backoff with jitter\n' +
            '  - offer a client-side maxRequestsPerSecond ceiling\n\n' +
            'All three need sleep. Rather than ship a throttle that does not throttle, or\n' +
            'a busy-wait that kills the transaction, the SDK surfaces the server\'s number\n' +
            'and puts the waiting in CheckQueueable, where System.enqueueJob can take a\n' +
            'delay.\n\n' +
            'For volume, prefer one bulk request over fifty single checks - it is one\n' +
            'rate-limit interaction instead of fifty, and one callout instead of fifty.'
        );
    }
}
