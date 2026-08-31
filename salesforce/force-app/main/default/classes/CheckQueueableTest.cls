@IsTest
private class CheckQueueableTest {
    private class Collector implements CheckQueueable.Handler {
        private final List<BulkCheckResult> results = new List<BulkCheckResult>();
        private final List<PactmanException> failures = new List<PactmanException>();

        public void handle(BulkCheckResult result) {
            results.add(result);
        }

        public void handleFailure(PactmanException error) {
            failures.add(error);
        }
    }

    private static Config config() {
        return new Config().withEndpoint('https://pactman.example');
    }

    @IsTest
    static void runsABatchAndHandsBackTheResult() {
        Test.setMock(HttpCalloutMock.class, new FixtureMock().withOrganization('411787097'));
        Collector collector = new Collector();

        Test.startTest();
        System.enqueueJob(
            new CheckQueueable(new List<String>{ '41-1787097', '99-6589560' }, collector, config())
        );
        Test.stopTest();

        Assert.areEqual(1, collector.results.size());
        Assert.areEqual(1, collector.results[0].organizations.size());
        Assert.areEqual(new List<String>{ '996589560' }, collector.results[0].notFoundEins);
        Assert.areEqual(0, collector.failures.size());
    }

    @IsTest
    static void reportsAFailureRatherThanSwallowingIt() {
        Test.setMock(HttpCalloutMock.class, new FixtureMock().withStatus(500));
        Collector collector = new Collector();

        Test.startTest();
        System.enqueueJob(new CheckQueueable(new List<String>{ '411787097' }, collector, config()));
        Test.stopTest();

        Assert.areEqual(0, collector.results.size());
        Assert.areEqual(1, collector.failures.size());
        Assert.isInstanceOfType(collector.failures[0], ServerException.class);
    }

    @IsTest
    static void aRateLimitIsRescheduledRatherThanReportedAsAFailure() {
        Test.setMock(
            HttpCalloutMock.class,
            new FixtureMock().withStatus(429).withHeader('Retry-After', '120')
        );
        Collector collector = new Collector();

        Test.startTest();
        System.enqueueJob(new CheckQueueable(new List<String>{ '411787097' }, collector, config()));
        Test.stopTest();

        // Chaining is suppressed inside a test transaction, so the observable
        // outcome is that nothing was reported as a permanent failure.
        Assert.areEqual(0, collector.results.size());
        Assert.areEqual(0, collector.failures.size());
    }

    @IsTest
    static void requiresAHandler() {
        try {
            new CheckQueueable(new List<String>{ '411787097' }, null);
            Assert.fail('Expected a ConfigurationException.');
        } catch (ConfigurationException e) {
            Assert.areEqual('CheckQueueable requires a Handler.', e.getMessage());
        }
    }

    @IsTest
    static void anEmptyListIsANoOp() {
        Collector collector = new Collector();

        Test.startTest();
        System.enqueueJob(new CheckQueueable(new List<String>(), collector, config()));
        Test.stopTest();

        Assert.areEqual(0, collector.results.size());
        Assert.areEqual(0, collector.failures.size());
    }
}
