@IsTest
private class TransportTest {
    private static Config config() {
        return new Config().withEndpoint('https://pactman.example');
    }

    @IsTest
    static void normalizeApiErrorsAcceptsEveryShapeTheApiSends() {
        Assert.areEqual(0, Transport.normalizeApiErrors(null).size());
        Assert.areEqual(0, Transport.normalizeApiErrors('   ').size());

        List<ApiErrorDetail> fromString = Transport.normalizeApiErrors('Something went wrong.');
        Assert.areEqual(1, fromString.size());
        Assert.areEqual('Something went wrong.', fromString[0].reason);

        List<ApiErrorDetail> fromObject = Transport.normalizeApiErrors(
            new Map<String, Object>{ 'reason' => 'single' }
        );
        Assert.areEqual(1, fromObject.size());

        List<ApiErrorDetail> fromList = Transport.normalizeApiErrors(new List<Object>{
            new Map<String, Object>{ 'reason' => 'a' },
            'not an object',
            new Map<String, Object>{ 'reason' => 'b' }
        });
        Assert.areEqual(2, fromList.size(), 'Non-object entries are dropped.');
    }

    @IsTest
    static void einsArriveAsEitherAListOrACommaSeparatedString() {
        ApiErrorDetail fromList = new ApiErrorDetail(new Map<String, Object>{
            'eins' => new List<Object>{ '411787097', 996589560, '996589560' }
        });
        Assert.areEqual(new List<String>{ '411787097', '996589560' }, fromList.eins);

        ApiErrorDetail fromString = new ApiErrorDetail(new Map<String, Object>{
            'eins' => '411787097, 996589560'
        });
        Assert.areEqual(new List<String>{ '411787097', '996589560' }, fromString.eins);

        Assert.areEqual(0, new ApiErrorDetail(new Map<String, Object>()).eins.size());
    }

    @IsTest
    static void retryAfterIsReadAsSeconds() {
        Test.setMock(HttpCalloutMock.class, new FixtureMock().withStatus(429).withHeader('Retry-After', '90'));

        Test.startTest();
        try {
            new Client(config()).nonprofits.check('411787097');
            Assert.fail('Expected a RateLimitException.');
        } catch (RateLimitException e) {
            Assert.areEqual(90, e.retryAfterSeconds.intValue());
        }
        Test.stopTest();
    }

    @IsTest
    static void retryAfterIsReadAsAnHttpDate() {
        Datetime soon = Datetime.now().addMinutes(2);
        String httpDate = soon.formatGmt('EEE, dd MMM yyyy HH:mm:ss') + ' GMT';
        Test.setMock(HttpCalloutMock.class, new FixtureMock().withStatus(429).withHeader('Retry-After', httpDate));

        Test.startTest();
        try {
            new Client(config()).nonprofits.check('411787097');
            Assert.fail('Expected a RateLimitException.');
        } catch (RateLimitException e) {
            Assert.isNotNull(e.retryAfterSeconds, 'An HTTP-date Retry-After should be converted.');
            Assert.isTrue(
                e.retryAfterSeconds > 30 && e.retryAfterSeconds <= 120,
                'Expected roughly two minutes, got ' + e.retryAfterSeconds
            );
        }
        Test.stopTest();
    }

    @IsTest
    static void anUnreadableRetryAfterIsNullRatherThanAGuess() {
        Test.setMock(HttpCalloutMock.class, new FixtureMock().withStatus(429).withHeader('Retry-After', 'soonish'));

        Test.startTest();
        try {
            new Client(config()).nonprofits.check('411787097');
            Assert.fail('Expected a RateLimitException.');
        } catch (RateLimitException e) {
            Assert.isNull(e.retryAfterSeconds);
        }
        Test.stopTest();
    }

    @IsTest
    static void requestIdFallsBackThroughTheHeaderNames() {
        FixtureMock mock = new FixtureMock().withOrganization('411787097');
        mock.withHeader('x-request-id', '').withHeader('x-correlation-id', 'corr-9');

        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        SingleCheckResult result = new Client(config()).nonprofits.check('411787097');
        Test.stopTest();

        Assert.areEqual('corr-9', result.requestId);
    }

    @IsTest
    static void anApiErrorPrefersTheReasonsFromTheErrorsArray() {
        Test.setMock(
            HttpCalloutMock.class,
            new FixtureMock().withStatus(400).withBody(
                '{"code":400,"message":"Bad Request","errors":[{"reason":"EIN 12 is malformed."},{"reason":"Try again."}]}'
            )
        );

        Test.startTest();
        try {
            new Client(config()).nonprofits.check('411787097');
            Assert.fail('Expected a BadRequestException.');
        } catch (BadRequestException e) {
            Assert.areEqual('EIN 12 is malformed.; Try again.', e.getMessage());
            Assert.areEqual('EIN 12 is malformed.; Try again.', e.apiMessage);
        }
        Test.stopTest();
    }

    @IsTest
    static void anApiErrorFallsBackToTheEnvelopeMessageThenTheBodyText() {
        List<ApiErrorDetail> none = new List<ApiErrorDetail>();
        Map<String, Object> envelope = new Map<String, Object>{ 'message' => 'Bad Request' };

        Assert.areEqual('Bad Request', Transport.apiMessageFor(envelope, none, envelope));
        Assert.areEqual(
            '<html>bad gateway</html>',
            Transport.apiMessageFor(new Map<String, Object>(), none, '  <html>bad gateway</html>  ')
        );
        Assert.areEqual(
            500,
            Transport.apiMessageFor(new Map<String, Object>(), none, 'x'.repeat(600)).length(),
            'A body that is not JSON is kept as evidence, but only its first 500 characters.'
        );
        Assert.isNull(Transport.apiMessageFor(new Map<String, Object>(), none, null));
    }

    @IsTest
    static void aNonJsonErrorBodyBecomesTheMessage() {
        Test.setMock(HttpCalloutMock.class, new FixtureMock().withStatus(502).withBody('<html>bad gateway</html>'));

        Test.startTest();
        try {
            new Client(config()).nonprofits.check('411787097');
            Assert.fail('Expected a ServerException.');
        } catch (ServerException e) {
            Assert.areEqual('<html>bad gateway</html>', e.getMessage());
        }
        Test.stopTest();
    }

    @IsTest
    static void aCalloutWithNoResponseIsRetriedOnceForASingleOrABulkCheck() {
        FlakyMock mock = new FlakyMock(new FixtureMock().withOrganization('411787097'));
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        SingleCheckResult single = new Client(config()).nonprofits.check('411787097');
        BulkCheckResult bulk = new Client(config()).nonprofits.checkBulk(new List<String>{ '411787097' });
        Test.stopTest();

        Assert.isNotNull(single.nonprofit);
        Assert.areEqual(1, bulk.organizations.size());
        Assert.areEqual(4, mock.calls, 'Each call lost its first response and succeeded on the immediate retry.');
    }

    /** Loses every other response, as a dropped connection would. */
    private class FlakyMock implements HttpCalloutMock {
        private final FixtureMock inner;
        public Integer calls = 0;

        private FlakyMock(FixtureMock inner) {
            this.inner = inner;
        }

        public HttpResponse respond(HttpRequest request) {
            calls++;

            if (Math.mod(calls, 2) == 1) {
                throw new CalloutException('Unexpected end of file from server');
            }

            return inner.respond(request);
        }
    }
}
