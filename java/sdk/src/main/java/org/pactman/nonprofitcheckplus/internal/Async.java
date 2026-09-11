package org.pactman.nonprofitcheckplus.internal;

import java.util.concurrent.CompletableFuture;
import java.util.concurrent.Executor;
import java.util.concurrent.FutureTask;
import java.util.function.Supplier;

/**
 * Runs blocking work on an executor and hands back a future that can really
 * cancel it.
 *
 * <p>Internal. {@code CompletableFuture.supplyAsync} would be shorter, but
 * cancelling the future it returns does not interrupt the thread already running
 * the work — the call would keep its socket and its retries going, invisibly,
 * after the caller had given up on it. Wrapping a {@link FutureTask} makes
 * {@code cancel(true)} reach the worker, which the transport observes as the
 * caller asking to stop.
 */
public final class Async {

    private Async() {
    }

    /**
     * Runs {@code work} on {@code executor}.
     *
     * @param <T>      the result type.
     * @param executor where the work runs.
     * @param work     the blocking call.
     * @return a future that completes with the result, and that interrupts the
     *         work when cancelled.
     */
    public static <T> CompletableFuture<T> supply(Executor executor, Supplier<T> work) {
        CompletableFuture<T> result = new CompletableFuture<>();

        FutureTask<Void> task = new FutureTask<>(() -> {
            try {
                result.complete(work.get());
            } catch (RuntimeException | Error failure) {
                result.completeExceptionally(failure);
            }
        }, null);

        result.whenComplete((value, error) -> {
            if (result.isCancelled()) {
                task.cancel(true);
            }
        });

        executor.execute(task);

        return result;
    }
}
