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
}
