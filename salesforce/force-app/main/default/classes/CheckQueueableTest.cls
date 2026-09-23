@IsTest
private class CheckQueueableTest {
    // A Queueable is serialized when it is enqueued, so the job runs against a
    // copy of the handler. Mutating instance state would be invisible to the
    // test that holds the original; statics survive the round trip.
    private static final List<BulkCheckResult> results = new List<BulkCheckResult>();
    private static final List<PactmanException> failures = new List<PactmanException>();

    private class Collector implements CheckQueueable.Handler {
        public void handle(BulkCheckResult result) {
            CheckQueueableTest.results.add(result);
        }

        public void handleFailure(PactmanException error) {
            CheckQueueableTest.failures.add(error);
        }
    }

    private static Config config() {
        return new Config().withEndpoint('https://pactman.example');
    }

    @IsTest
    static void runsABatchAndHandsBackTheResult() {
        Test.setMock(HttpCalloutMock.class, new FixtureMock().withOrganization('411787097'));

        Test.startTest();
        System.enqueueJob(
            new CheckQueueable(
                new List<String>{ '41-1787097', '99-6589560' },
                new Collector(),
                config()
            )
        );
        Test.stopTest();

        Assert.areEqual(1, results.size());
        Assert.areEqual(1, results[0].organizations.size());
        Assert.areEqual(new List<String>{ '996589560' }, results[0].notFoundEins);
        Assert.areEqual(0, failures.size());
    }

    @IsTest
    static void reportsAFailureRatherThanSwallowingIt() {
        Test.setMock(HttpCalloutMock.class, new FixtureMock().withStatus(500));

        Test.startTest();
        System.enqueueJob(
            new CheckQueueable(new List<String>{ '411787097' }, new Collector(), config())
        );
        Test.stopTest();

        Assert.areEqual(0, results.size());
        Assert.areEqual(1, failures.size());
        Assert.isInstanceOfType(failures[0], ServerException.class);
    }

    @IsTest
    static void aRateLimitIsRescheduledRatherThanReportedAsAFailure() {
        Test.setMock(
            HttpCalloutMock.class,
            new FixtureMock().withStatus(429).withHeader('Retry-After', '120')
        );

        Test.startTest();
        System.enqueueJob(
            new CheckQueueable(new List<String>{ '411787097' }, new Collector(), config())
        );
        Test.stopTest();

        // Chaining is suppressed inside a test transaction, so the observable
        // outcome is that nothing was reported as a permanent failure.
        Assert.areEqual(0, results.size());
        Assert.areEqual(0, failures.size());
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

        Test.startTest();
        System.enqueueJob(new CheckQueueable(new List<String>(), new Collector(), config()));
        Test.stopTest();

        Assert.areEqual(0, results.size());
        Assert.areEqual(0, failures.size());
    }
}
