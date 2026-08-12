/**
 * EX-22 — Rate-limit response and Retry-After.
 *
 * HTTP 429 becomes `PactmanRateLimitError`, carrying the status, the server's
 * `Retry-After` when it sent one, and sanitized request metadata.
 *
 * Three behaviours are shown: surfacing the error with retries off, letting the
 * bounded retry policy honour `Retry-After`, and reducing pressure with a
 * client-side ceiling plus a bounded concurrency pool.
 *
 * Run:  PACTMAN_API_KEY=... node examples/ex-22-rate-limit.mjs
 */
import { PactmanClient, PactmanRateLimitError } from '@pactmandev/nonprofit-check-plus';
import { CONTROL_EINS, FIXTURE_EINS, withFixtureApi } from './lib/fixture-api.mjs';
import { requireApiKey } from './lib/client.mjs';
import { bullet, field, heading, note } from './lib/print.mjs';

/** Runs tasks with at most `limit` in flight. The SDK does not queue for you. */
async function withConcurrency(items, limit, worker) {
  const results = [];
  const queue = [...items.entries()];

  const runners = Array.from({ length: Math.min(limit, queue.length) }, async () => {
    for (;;) {
      const next = queue.shift();

      if (!next) {
        return;
      }

      const [index, item] = next;
      results[index] = await worker(item);
    }
  });

  await Promise.all(runners);

  return results;
}

await withFixtureApi(async (client, baseUrl) => {
  // 1. Retries off, so the 429 reaches the caller untouched.
  heading('Surfacing the error');

  try {
    await client.nonprofits.check(CONTROL_EINS.rateLimited, { retry: false });
    console.log('  Unexpectedly succeeded.');
  } catch (error) {
    if (!(error instanceof PactmanRateLimitError)) {
      throw error;
    }

    field('class', error.constructor.name);
    field('category', error.category);
    field('status', error.status);
    field('retryAfterSeconds', error.retryAfterSeconds);
    field('requestId', error.requestId);
    field('attempts', error.attempts);
    field('apiMessage', error.apiMessage);

    for (const detail of error.apiErrors) {
      bullet(`${detail.resource}: ${detail.reason}`);
    }

    // Safe to log wholesale — no credential reaches any of these fields.
    field('toJSON contains the key', JSON.stringify(error).includes(process.env.PACTMAN_API_KEY));

    // Schedule your own backoff from the server's number when you handle 429s
    // yourself. Fall back to your own delay when it is absent.
    const retryAt = new Date(Date.now() + (error.retryAfterSeconds ?? 5) * 1000);
    field('would retry at', retryAt.toISOString());
  }

  // 2. Bounded automatic retry. 429 is retryable and `Retry-After` wins over
  //    computed backoff, so the SDK waits exactly as long as it was told to.
  heading('Bounded automatic retry');

  const startedAt = Date.now();

  try {
    await client.nonprofits.check(CONTROL_EINS.rateLimited, {
      retry: { maxRetries: 1, respectRetryAfter: true },
    });
    console.log('  Unexpectedly succeeded.');
  } catch (error) {
    field('class', error.constructor.name);
    field('attempts', error.attempts);
    field('elapsed (ms)', Date.now() - startedAt);
    bullet('The retry honoured Retry-After, then gave up at the configured bound.');
    bullet('Retries stay finite; the SDK never retries indefinitely.');
  }

  // 3. Reduce pressure rather than absorb rejections: cap outbound rate and keep
  //    your own concurrency small. Prefer one bulk call to many single ones.
  heading('Reducing pressure');

  const paced = new PactmanClient({
    apiKey: requireApiKey(),
    baseUrl,
    maxRequestsPerSecond: 3,
    retry: { maxRetries: 2 },
  });

  const eins = [
    FIXTURE_EINS.publicCharity,
    FIXTURE_EINS.publicCharitySecond,
    FIXTURE_EINS.privateFoundation,
    FIXTURE_EINS.reinstated,
  ];

  const begin = Date.now();

  const names = await withConcurrency(eins, 2, async ein => {
    const { nonprofit } = await paced.nonprofits.check(ein);

    return nonprofit?.organization_name ?? 'no record';
  });

  field('maxRequestsPerSecond', 3);
  field('concurrency limit', 2);
  field('requests', names.length);
  field('elapsed (ms)', Date.now() - begin);

  for (const name of names) {
    bullet(name);
  }
});

note(
  'The server\'s limits are authoritative and can change per account and endpoint.\n' +
    'Treat maxRequestsPerSecond as a courtesy throttle, not a guarantee, and prefer\n' +
    'the bulk endpoint over a fan-out of single checks.',
);
