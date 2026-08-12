/**
 * EX-23 — Transient network or server failure.
 *
 * Retries are on by default: two of them, exponential backoff from 500ms with
 * full jitter, capped at 8 seconds per delay. Eligible are 429, 500, 502, 503,
 * 504 and connection failures that produced no response.
 *
 * Never retried, whatever `retryableStatuses` contains: 400, 401, 403, 404, and
 * anything rejected by local validation. Retrying a rejected API key just burns
 * the same key three times; retrying a 404 cannot make a record exist.
 *
 * Run:  PACTMAN_API_KEY=... node examples/ex-23-transient-retries.mjs
 */
import {
  PactmanAuthenticationError,
  PactmanClient,
  PactmanNetworkError,
  PactmanNotFoundError,
  PactmanValidationError,
} from '@pactmandev/nonprofit-check-plus';
import { CONTROL_EINS, FIXTURE_EINS, withFixtureApi } from './lib/fixture-api.mjs';
import { bullet, field, heading, note } from './lib/print.mjs';

await withFixtureApi(async (client, baseUrl) => {
  // The fixture endpoint answers 503 twice, then succeeds — a textbook transient
  // failure. Delays are shortened here so the example runs quickly; the defaults
  // are 500ms initial and 8s maximum.
  heading('A 503 that clears on retry');

  const startedAt = Date.now();

  const result = await client.nonprofits.check(CONTROL_EINS.transientFailure, {
    retry: { maxRetries: 3, initialDelayMs: 40, maxDelayMs: 400 },
  });

  field('status', result.status);
  field('organization', result.nonprofit?.organization_name);
  field('elapsed (ms)', Date.now() - startedAt);
  bullet('Two 503s were absorbed; the caller saw one successful result.');
  bullet('Backoff grows exponentially and is jittered, so parallel clients scatter.');

  heading('The same failure with retries disabled');

  try {
    await client.nonprofits.check(CONTROL_EINS.transientFailure, { retry: false });
    console.log('  Unexpectedly succeeded.');
  } catch (error) {
    field('class', error.constructor.name);
    field('status', error.status);
    field('attempts', error.attempts);
    field('apiMessage', error.apiMessage);
  }

  heading('Failures that are never retried');

  // 404 — a definite answer. Retrying cannot change it.
  try {
    await client.nonprofits.check(FIXTURE_EINS.noRecord, {
      retry: { maxRetries: 5, retryableStatuses: [404, 500] },
    });
  } catch (error) {
    if (!(error instanceof PactmanNotFoundError)) {
      throw error;
    }

    field('404 attempts', `${error.attempts} — not retried even though 404 was listed`);
  }

  // 401 — retrying a rejected credential achieves nothing.
  const badKeyClient = new PactmanClient({
    apiKey: 'obviously-not-a-real-key',
    baseUrl,
    retry: { maxRetries: 3 },
  });

  try {
    await badKeyClient.nonprofits.check(FIXTURE_EINS.publicCharity);
  } catch (error) {
    if (!(error instanceof PactmanAuthenticationError)) {
      throw error;
    }

    field('401 attempts', `${error.attempts} — authentication failures are terminal`);
  }

  // Local validation — nothing was sent, so there is nothing to retry.
  try {
    await client.nonprofits.check('not-an-ein', { retry: { maxRetries: 3 } });
  } catch (error) {
    if (!(error instanceof PactmanValidationError)) {
      throw error;
    }

    field('validation', `origin=${error.origin} — rejected before any request`);
  }

  // A connection that never reaches a server: retried, then surfaced as a
  // network error carrying the attempt count.
  heading('A connection failure');

  const unreachable = new PactmanClient({
    apiKey: process.env.PACTMAN_API_KEY,
    baseUrl: 'http://127.0.0.1:1',
    retry: { maxRetries: 2, initialDelayMs: 20, maxDelayMs: 60 },
    timeoutMs: 2_000,
  });

  try {
    await unreachable.nonprofits.check(FIXTURE_EINS.publicCharity);
  } catch (error) {
    if (!(error instanceof PactmanNetworkError)) {
      throw error;
    }

    field('class', error.constructor.name);
    field('category', error.category);
    field('attempts', error.attempts);
    field('message', error.message);
  }
});

note(
  'A retried failure that eventually succeeds is a success. A retried failure that\n' +
    'exhausts its budget is an outage — record it as "not checked", never as a pass.',
);
