@IsTest
private class ClientTest {
    private static Config config() {
        return new Config().withEndpoint('https://pactman.example');
    }

    @IsTest
    static void checkReturnsTheOrganizationAndEnvelope() {
        Test.setMock(HttpCalloutMock.class, new FixtureMock().withOrganization('41-1787097').withCheckCount(17));

        Test.startTest();
        SingleCheckResult result = new Client(config()).nonprofits.check('41-1787097');
        Test.stopTest();

        Assert.areEqual(200, result.status);
        Assert.areEqual('411787097', result.nonprofit.ein);
        Assert.areEqual('Fixture Charitable Trust', result.nonprofit.organization_name);
        Assert.areEqual(17, result.checkCount);
        Assert.areEqual(42, result.timeTakenMs.intValue());
        Assert.areEqual('fixture-request-id', result.requestId);
        Assert.areEqual(0, result.errors.size());
        Assert.isTrue(result.raw instanceof Map<String, Object>);
    }

    @IsTest
    static void anUnknownEinIsANotFoundException() {
        Test.setMock(HttpCalloutMock.class, new FixtureMock());

        Test.startTest();
        try {
            new Client(config()).nonprofits.check('99-6589560');
            Assert.fail('Expected a NotFoundException.');
        } catch (NotFoundException e) {
            Assert.areEqual(404, e.status);
            Assert.areEqual(ErrorCategory.NOT_FOUND, e.category);
            Assert.areEqual(ErrorOrigin.API, e.origin);
            Assert.areEqual(1, e.attempts);
        }
        Test.stopTest();
    }

    @IsTest
    static void aMalformedEinNeverReachesTheNetwork() {
        Test.setMock(HttpCalloutMock.class, new FixtureMock());

        Test.startTest();
        try {
            new Client(config()).nonprofits.check('nope');
            Assert.fail('Expected a ValidationException.');
        } catch (ValidationException e) {
            Assert.areEqual(ErrorOrigin.LOCAL, e.origin);
        }
        Assert.areEqual(0, Limits.getCallouts(), 'No callout should have been made.');
        Test.stopTest();
    }

    @IsTest
    static void bulkSeparatesMatchesFromMisses() {
        Test.setMock(HttpCalloutMock.class, new FixtureMock().withOrganization('411787097'));

        Test.startTest();
        BulkCheckResult result = new Client(config()).nonprofits.checkBulk(
            new List<String>{ '41-1787097', '99-6589560' }
        );
        Test.stopTest();

        Assert.areEqual(200, result.status);
        Assert.areEqual(1, result.organizations.size());
        Assert.areEqual(new List<String>{ '996589560' }, result.notFoundEins);
        Assert.areEqual(1, result.errors.size());
        Assert.areEqual('411787097', new List<String>(result.byEin().keySet())[0]);
    }

    @IsTest
    static void bulkRefusesAnEmptyBatch() {
        try {
            new Client(config()).nonprofits.checkBulk(new List<String>());
            Assert.fail('Expected a ValidationException.');
        } catch (ValidationException e) {
            Assert.areEqual('checkBulk requires at least one EIN.', e.getMessage());
        }
    }

    @IsTest
    static void bulkRefusesMoreThanTheApiAccepts() {
        List<String> eins = new List<String>();

        for (Integer i = 0; i < Constants.MAX_BULK_EINS + 1; i++) {
            eins.add('411787097');
        }

        try {
            new Client(config()).nonprofits.checkBulk(eins);
            Assert.fail('Expected a ValidationException.');
        } catch (ValidationException e) {
            Assert.isTrue(e.getMessage().contains('at most 50'), e.getMessage());
            Assert.isTrue(e.getMessage().contains('Ein.chunk'), e.getMessage());
        }
    }

    @IsTest
    static void duplicatesAreSentAsSuppliedUnlessDedupeIsSet() {
        RecordingMock mock = new RecordingMock(new FixtureMock().withOrganization('411787097'));
        Test.setMock(HttpCalloutMock.class, mock);
        List<String> eins = new List<String>{ '41-1787097', '411787097', '41-1787097' };

        Test.startTest();
        new Client(config()).nonprofits.checkBulk(eins);
        String sentAsSupplied = mock.lastBody;

        new Client(config()).nonprofits.checkBulk(eins, new RequestOptions().withDedupe(true));
        String sentDeduped = mock.lastBody;
        Test.stopTest();

        // Each EIN consumes quota, so what was sent is what was billed.
        Assert.areEqual('["411787097","411787097","411787097"]', sentAsSupplied);
        Assert.areEqual('["411787097"]', sentDeduped);
    }

    @IsTest
    static void requestsCarryTheSdkUserAgentAndNoAuthorization() {
        RecordingMock mock = new RecordingMock(new FixtureMock().withOrganization('411787097'));
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        new Client(config()).nonprofits.check('411787097');
        Test.stopTest();

        Assert.areEqual(SdkVersion.userAgent(), mock.lastRequest.getHeader('User-Agent'));
        Assert.areEqual('application/json', mock.lastRequest.getHeader('Accept'));
        Assert.isNull(
            mock.lastRequest.getHeader('Authorization'),
            'Apex never sets Authorization; the platform injects it from the External Credential.'
        );
    }

    @IsTest
    static void perRequestHeadersReachTheRequest() {
        RecordingMock mock = new RecordingMock(new FixtureMock().withOrganization('411787097'));
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        new Client(config().withHeader('X-Team', 'grants'))
            .nonprofits.check('411787097', new RequestOptions().withHeader('X-Case', 'c-1'));
        Test.stopTest();

        Assert.areEqual('grants', mock.lastRequest.getHeader('X-Team'));
        Assert.areEqual('c-1', mock.lastRequest.getHeader('X-Case'));
    }

    @IsTest
    static void aRateLimitCarriesRetryAfter() {
        Test.setMock(
            HttpCalloutMock.class,
            new FixtureMock().withStatus(429).withMessage('Slow down.').withHeader('Retry-After', '30')
        );

        Test.startTest();
        try {
            new Client(config()).nonprofits.check('411787097');
            Assert.fail('Expected a RateLimitException.');
        } catch (RateLimitException e) {
            Assert.areEqual('Slow down.', e.getMessage());
            Assert.areEqual(30, e.retryAfterSeconds.intValue());
            Assert.areEqual(ErrorCategory.RATE_LIMIT, e.category);
        }
        Test.stopTest();
    }

    @IsTest
    static void aNonJsonBodyIsKeptAsEvidence() {
        Test.setMock(HttpCalloutMock.class, new FixtureMock().withBody('<html>maintenance</html>'));

        Test.startTest();
        SingleCheckResult result = new Client(config()).nonprofits.check('411787097');
        Test.stopTest();

        Assert.areEqual('<html>maintenance</html>', (String) result.raw);
        Assert.isNull(result.nonprofit);
        Assert.isNull(result.checkCount);
    }

    @IsTest
    static void serverErrorsMapToServerException() {
        Test.setMock(HttpCalloutMock.class, new FixtureMock().withStatus(503));

        Test.startTest();
        try {
            new Client(config()).nonprofits.check('411787097');
            Assert.fail('Expected a ServerException.');
        } catch (ServerException e) {
            Assert.areEqual(503, e.status);
            Assert.areEqual(1, e.attempts, 'A 5xx is not retried in-transaction.');
        }
        Test.stopTest();
    }

    /** Captures what was actually sent, then delegates to the packaged fixture. */
    private class RecordingMock implements HttpCalloutMock {
        private final FixtureMock inner;
        public HttpRequest lastRequest;
        public String lastBody;

        private RecordingMock(FixtureMock inner) {
            this.inner = inner;
        }

        public HttpResponse respond(HttpRequest request) {
            lastRequest = request;
            lastBody = request.getBody();
            return inner.respond(request);
        }
    }

    @IsTest
    static void theDefaultClientUsesTheNamedCredential() {
        Client client = new Client();

        Assert.areEqual(Constants.DEFAULT_NAMED_CREDENTIAL, client.configuration.namedCredential);
        Assert.isTrue(client.toString().contains('callout:'), client.toString());
        Assert.isNotNull(client.nonprofits);
    }
}
