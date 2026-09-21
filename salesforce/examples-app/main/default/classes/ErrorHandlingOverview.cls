/**
 * Error handling — branching on error type, with no string parsing.
 */
@IsTest
private class ErrorHandlingOverview {
    @IsTest
    static void turnsEveryFailureIntoAnAction() {
        Test.setMock(HttpCalloutMock.class, new ExampleApiMock());
        Client client = ExampleApiMock.client();

        Test.startTest();

        // 1. A malformed EIN never leaves the org.
        String malformed = outcome(client, '41178709');
        ExampleOutput.field('malformed EIN', malformed);
        Assert.isTrue(malformed.startsWith('Local validation'), malformed);

        // 2. An empty batch is rejected locally too.
        String emptyBatch;

        try {
            client.nonprofits.checkBulk(new List<String>());
            emptyBatch = 'unexpectedly succeeded';
        } catch (PactmanException e) {
            emptyBatch = explain(e);
        }

        ExampleOutput.field('empty batch', emptyBatch);
        Assert.isTrue(emptyBatch.startsWith('Local validation'), emptyBatch);

        // 3. A rejected key produces an authentication error on first use. Apex
        //    never holds the key — the External Credential does — so the 401 is
        //    what a revoked or mistyped key there looks like.
        Test.setMock(HttpCalloutMock.class, new FixtureMock().withStatus(401));
        String badKey = outcome(client, '411787097');
        ExampleOutput.field('bad key', badKey);
        Assert.isTrue(badKey.startsWith('Authentication'), badKey);

        // 4. A real call, handled the same way.
        Test.setMock(HttpCalloutMock.class, new ExampleApiMock());
        String valid = outcome(client, '41-1787097');
        ExampleOutput.field('valid check', valid);
        Assert.isFalse(valid.startsWith('Unexpected'), valid);

        Test.stopTest();
    }

    private static String outcome(Client client, String ein) {
        try {
            SingleCheckResult result = client.nonprofits.check(ein);
            return result.nonprofit == null ? 'no record' : result.nonprofit.organization_name;
        } catch (PactmanException e) {
            return explain(e);
        }
    }

    /** One place to turn any SDK failure into an action. No string parsing. */
    private static String explain(PactmanException error) {
        if (error instanceof ValidationException) {
            ValidationException invalid = (ValidationException) error;
            List<String> messages = new List<String>();

            for (ValidationIssue issue : invalid.issues) {
                messages.add(issue.message);
            }

            return 'Local validation — fix the input. ' +
                (messages.isEmpty() ? invalid.getMessage() : String.join(messages, ' '));
        }

        if (error instanceof AuthenticationException) {
            return 'Authentication — the API key was rejected. Check the External Credential.';
        }

        if (error instanceof RateLimitException) {
            Decimal retryAfter = ((RateLimitException) error).retryAfterSeconds;
            return 'Rate limited — retry after ' + (retryAfter == null ? 'an unspecified' : String.valueOf(retryAfter)) +
                ' seconds.';
        }

        if (error instanceof TimeoutException) {
            return 'Timed out after ' + ((TimeoutException) error).timeoutMs + 'ms — raise timeoutMs or retry later.';
        }

        if (error instanceof NetworkException) {
            return 'Network failure — the request never reached the API.';
        }

        if (error instanceof ApiException) {
            ApiException api = (ApiException) error;
            return 'API error ' + api.status + ' (request ' + (api.requestId == null ? 'unknown' : api.requestId) +
                '): ' + api.getMessage();
        }

        return 'Unexpected: ' + error.getMessage();
    }
}
