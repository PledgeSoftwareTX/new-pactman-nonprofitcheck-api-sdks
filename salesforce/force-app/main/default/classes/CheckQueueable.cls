/**
 * Runs nonprofit checks asynchronously.
 *
 * **This is the entry point most orgs actually need.** Callouts are illegal
 * from a trigger and after DML in the same transaction, which is exactly where
 * verification tends to belong. This job takes any number of EINs, sends them
 * {@link Constants.MAX_BULK_EINS} at a time, and chains itself until they are
 * all done.
 *
 * It is also the only place this SDK can do real backoff. Apex has no sleep, so
 * {@link Transport} never waits out a `Retry-After` in-transaction; this job
 * re-enqueues itself with a delay instead, which is the one genuine backoff
 * mechanism the platform offers.
 *
 * ```
 * System.enqueueJob(new pactman.CheckQueueable(eins, new MyHandler()));
 * ```
 */
global class CheckQueueable implements Queueable, Database.AllowsCallouts {
    /** Receives each batch's outcome. Implement this in the subscriber org. */
    global interface Handler {
        /** Called once per successful batch, in the order the batches were sent. */
        void handle(BulkCheckResult result);

        /** Called when a batch fails. The remaining batches are abandoned. */
        void handleFailure(PactmanException error);
    }

    /** Salesforce's ceiling on a delayed enqueue, in minutes. */
    private static final Integer MAX_DELAY_MINUTES = 10;

    private final List<String> pending;
    private final Handler handler;
    private final Config configuration;

    global CheckQueueable(List<String> eins, Handler handler) {
        this(eins, handler, new Config());
    }

    global CheckQueueable(List<String> eins, Handler handler, Config configuration) {
        if (handler == null) {
            throw Errors.configuration('CheckQueueable requires a Handler.');
        }

        this.pending = eins == null ? new List<String>() : eins.clone();
        this.handler = handler;
        this.configuration = configuration == null ? new Config() : configuration;
    }

    global void execute(QueueableContext context) {
        if (pending.isEmpty()) {
            return;
        }

        List<String> batch = new List<String>();
        List<String> remainder = new List<String>();

        for (Integer i = 0; i < pending.size(); i++) {
            if (i < Constants.MAX_BULK_EINS) {
                batch.add(pending[i]);
            } else {
                remainder.add(pending[i]);
            }
        }

        try {
            BulkCheckResult result = new Client(configuration).nonprofits.checkBulk(batch);
            handler.handle(result);
        } catch (RateLimitException e) {
            // The whole batch, unsent, goes back on the queue after the server's
            // own delay. Nothing was consumed, so nothing is lost by retrying.
            reschedule(pending, delayMinutesFor(e.retryAfterSeconds));
            return;
        } catch (PactmanException e) {
            handler.handleFailure(e);
            return;
        }

        if (!remainder.isEmpty()) {
            reschedule(remainder, 0);
        }
    }

    /**
     * Converts a `Retry-After` in seconds to a delay Salesforce will accept.
     *
     * Rounds up to whole minutes and clamps to the platform's 10-minute
     * ceiling. A missing value becomes one minute rather than an immediate
     * retry, which would just be rate-limited again.
     */
    private Integer delayMinutesFor(Decimal retryAfterSeconds) {
        if (retryAfterSeconds == null || retryAfterSeconds <= 0) {
            return 1;
        }

        Integer minutes = (retryAfterSeconds / 60).round(System.RoundingMode.UP).intValue();
        return Math.min(Math.max(minutes, 1), MAX_DELAY_MINUTES);
    }

    private void reschedule(List<String> eins, Integer delayMinutes) {
        if (Limits.getQueueableJobs() >= Limits.getLimitQueueableJobs()) {
            handler.handleFailure(Errors.configuration(
                'This transaction cannot enqueue another job, so ' + eins.size() +
                    ' EINs were not checked. Start the run from a lower stack depth, or ' +
                    'move it into Batch Apex.'
            ));
            return;
        }

        // Apex forbids chaining a Queueable from inside a test transaction.
        if (Test.isRunningTest()) {
            return;
        }

        System.enqueueJob(new CheckQueueable(eins, handler, configuration), delayMinutes);
    }
}
