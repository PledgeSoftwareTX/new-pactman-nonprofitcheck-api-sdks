/**
 * EX-24 — Timeout and request cancellation.
 *
 * The timeout is always finite — 30 seconds by default, configurable per client
 * or per request, and impossible to disable. Cancellation is Node's own
 * `AbortSignal`.
 *
 * The two are different events and stay different types:
 *
 *   PactmanTimeoutError   the deadline you configured expired
 *   PactmanNetworkError   you aborted; category `network`, origin `local`
 *
 * Conflating them hides which side gave up. A timeout usually means raise the
 * budget or shed load; a cancellation means the caller went away.
 *
 * Run:  PACTMAN_API_KEY=... node examples/ex-24-timeout-and-cancellation.mjs
 */
import { PactmanNetworkError, PactmanTimeoutError } from '@pactmandev/nonprofit-check-plus';
import { CONTROL_EINS, withFixtureApi } from './lib/fixture-api.mjs';
import { bullet, field, heading, note } from './lib/print.mjs';

await withFixtureApi(async client => {
  // The fixture endpoint holds the response open, so a short deadline expires.
  heading('A per-request timeout');

  const timeoutStartedAt = Date.now();

  try {
    await client.nonprofits.check(CONTROL_EINS.slow, { timeoutMs: 250, retry: false });
    console.log('  Unexpectedly succeeded.');
  } catch (error) {
    if (!(error instanceof PactmanTimeoutError)) {
      throw error;
    }

    field('class', error.constructor.name);
    field('category', error.category);
    field('origin', error.origin);
    field('timeoutMs', error.timeoutMs);
    field('attempts', error.attempts);
    field('elapsed (ms)', Date.now() - timeoutStartedAt);
    field('is a cancellation', error instanceof PactmanNetworkError);
  }

  // Cancellation. The signal aborts the in-flight request and every retry that
  // was still planned, so nothing keeps running after you have stopped caring.
  heading('Caller cancellation with AbortSignal');

  const controller = new AbortController();
  const cancelStartedAt = Date.now();

  // Always clear the timer, whichever way the race ends — a stray timer is
  // exactly the unbounded background work this example is meant to avoid.
  const cancelTimer = setTimeout(() => controller.abort(new Error('user navigated away')), 200);

  try {
    await client.nonprofits.check(CONTROL_EINS.slow, {
      signal: controller.signal,
      timeoutMs: 10_000,
    });
    console.log('  Unexpectedly succeeded.');
  } catch (error) {
    if (!(error instanceof PactmanNetworkError)) {
      throw error;
    }

    field('class', error.constructor.name);
    field('category', error.category);
    field('origin', error.origin);
    field('elapsed (ms)', Date.now() - cancelStartedAt);
    field('is a timeout', error instanceof PactmanTimeoutError);
    field('cause', String(error.cause?.message ?? error.cause));
  } finally {
    clearTimeout(cancelTimer);
  }

  // One handler, two outcomes, no string matching.
  heading('Distinguishing them in one handler');

  function classify(error) {
    if (error instanceof PactmanTimeoutError) {
      return `timeout after ${error.timeoutMs}ms — raise the budget or shed load`;
    }

    if (error instanceof PactmanNetworkError) {
      return 'cancelled or unreachable — the caller stopped, or nothing answered';
    }

    return 'something else entirely';
  }

  for (const [label, run] of [
    ['deadline', () => client.nonprofits.check(CONTROL_EINS.slow, { timeoutMs: 150, retry: false })],
    [
      'abort',
      () => {
        const local = new AbortController();
        local.abort();

        return client.nonprofits.check(CONTROL_EINS.slow, { signal: local.signal });
      },
    ],
  ]) {
    try {
      await run();
      console.log(`  ${label}: unexpectedly succeeded`);
    } catch (error) {
      field(label, classify(error));
    }
  }

  // An already-aborted signal is rejected before a socket is opened.
  bullet('Aborting before the call means no request is made at all.');
  bullet('Aborting mid-flight cancels the attempt and any retries still planned.');
});

note(
  'There is no way to disable the timeout, by design. An unbounded request holds a\n' +
    'connection, a worker, and a caller\'s patience for as long as the network lets it.',
);
