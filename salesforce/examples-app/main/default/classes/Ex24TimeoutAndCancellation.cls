/**
 * EX-24 — Timeouts, and why there is no cancellation.
 *
 * The timeout is always finite and there is no way to disable it. A timeout
 * arrives as {@link TimeoutException}, which is distinct from
 * {@link NetworkException} — the first means the budget expired, the second
 * means no response was produced at all.
 *
 * **Cancellation has no Apex equivalent.** There is no `AbortSignal`, no
 * `CancellationToken` and no context to cancel: a synchronous callout runs to
 * its timeout or to its answer. What Apex has instead are two hard budgets,
 * and this example shows both.
 */
@IsTest
private class Ex24TimeoutAndCancellation {
    @IsTest
    static void reportsTimeoutsAndRefusesAnImpossibleBudget() {
        ExampleApiMock api = new ExampleApiMock();
        Test.setMock(HttpCalloutMock.class, api);

        ExampleOutput.heading('The budgets');
        ExampleOutput.field('Constants.DEFAULT_TIMEOUT_MS', Constants.DEFAULT_TIMEOUT_MS);
        ExampleOutput.field('Constants.MAX_TIMEOUT_MS', Constants.MAX_TIMEOUT_MS);
        ExampleOutput.field('callouts per transaction', Limits.getLimitCallouts());

        Test.startTest();

        ExampleOutput.heading('A per-request timeout');

        try {
            ExampleApiMock.client()
                .nonprofits.check(
                    ExampleFixtures.CONTROL_SLOW,
                    new RequestOptions().withTimeoutMs(5000)
                );
            Assert.fail('Expected the request to time out.');
        } catch (TimeoutException e) {
            ExampleOutput.field('exception', 'TimeoutException');
            ExampleOutput.field('category', Errors.wireValue(e.category));
            ExampleOutput.field('origin', Errors.wireValue(e.origin));
            ExampleOutput.field('timeoutMs', e.timeoutMs);
            ExampleOutput.field('attempts', e.attempts);

            Assert.areEqual(ErrorCategory.TIMEOUT, e.category);
            Assert.areEqual(ErrorOrigin.LOCAL, e.origin);
            Assert.areEqual(5000, e.timeoutMs, 'The per-request budget, not the client default.');
            Assert.areEqual(
                1,
                e.attempts,
                'A timeout is never retried: it has already spent its share of the budget.'
            );
        }

        Test.stopTest();

        // The client's own budget is untouched by a per-request override.
        ExampleOutput.field(
            'client timeout after',
            ExampleApiMock.config().timeoutMs
        );
        Assert.areEqual(Constants.DEFAULT_TIMEOUT_MS, ExampleApiMock.config().timeoutMs);

        ExampleOutput.heading('A budget the platform will not accept');

        try {
            new RequestOptions().withTimeoutMs(Constants.MAX_TIMEOUT_MS + 1);
            Assert.fail('A timeout above the platform ceiling should have been refused.');
        } catch (ConfigurationException e) {
            ExampleOutput.field('message', e.getMessage());
        }

        try {
            new RequestOptions().withTimeoutMs(0);
            Assert.fail('A non-positive timeout should have been refused.');
        } catch (ConfigurationException e) {
            ExampleOutput.field('message', e.getMessage());
        }

        ExampleOutput.note(
            'Two exceptions, two different facts:\n\n' +
            '  TimeoutException  - the callout budget expired. Raise it, or shed load.\n' +
            '  NetworkException  - no HTTP response was produced at all. See ex-23.\n\n' +
            'Cancellation is the one thing in this series with no Apex equivalent. There\n' +
            'is no signal to abort a running callout, so the SDK refuses a timeout above\n' +
            'the platform ceiling up front rather than letting the callout fail at send\n' +
            'time, and it refuses to send at all once the transaction has used all 100 of\n' +
            'its callouts - a clear message beats a bare governor limit.\n\n' +
            'The binding constraint is usually not the per-callout timeout but the\n' +
            '120 seconds of cumulative callout time a transaction gets. Budget for the\n' +
            'batch, not the request.'
        );
    }
}
