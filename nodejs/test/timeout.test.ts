import { describe, expect, it } from 'vitest';
import { PactmanClient } from '../src/client.js';
import { PactmanNetworkError, PactmanTimeoutError } from '../src/errors.js';
import { DEFAULT_TIMEOUT_MS, type FetchLike } from '../src/config.js';
import { captureError, createClock, envelope, nonprofitFixture, TEST_API_KEY } from './helpers.js';

const BASE_URL = 'http://mock.test';

/** A fetch that never settles until its signal aborts, as a real fetch would. */
function hangingFetch(onRequest?: () => void): FetchLike {
  return (_url, init) => {
    onRequest?.();

    return new Promise((_resolve, reject) => {
      const abort = () => reject(new DOMException('This operation was aborted', 'AbortError'));

      if (init.signal?.aborted) {
        abort();
        return;
      }

      init.signal?.addEventListener('abort', abort, { once: true });
    });
  };
}

describe('timeouts', () => {
  it('documents a finite default timeout', () => {
    expect(Number.isFinite(DEFAULT_TIMEOUT_MS)).toBe(true);
    expect(new PactmanClient({ apiKey: TEST_API_KEY }).timeoutMs).toBe(DEFAULT_TIMEOUT_MS);
  });

  it('produces a timeout error when the endpoint exceeds the configured timeout', async () => {
    const client = new PactmanClient(
      { apiKey: TEST_API_KEY, baseUrl: BASE_URL, fetch: hangingFetch(), timeoutMs: 10, retry: false },
      createClock(),
    );

    const error = await captureError<PactmanTimeoutError>(client.nonprofits.check('411787097'));

    expect(error).toBeInstanceOf(PactmanTimeoutError);
    expect(error.category).toBe('timeout');
    expect(error.timeoutMs).toBe(10);
  });

  it('lets a per-request timeout override the client default', async () => {
    const client = new PactmanClient(
      { apiKey: TEST_API_KEY, baseUrl: BASE_URL, fetch: hangingFetch(), timeoutMs: 5_000, retry: false },
      createClock(),
    );

    const started = Date.now();
    const error = await captureError<PactmanTimeoutError>(
      client.nonprofits.check('411787097', { timeoutMs: 15 }),
    );

    expect(error).toBeInstanceOf(PactmanTimeoutError);
    expect(error.timeoutMs).toBe(15);
    expect(Date.now() - started).toBeLessThan(1_000);
  });

  it('retries a timeout when the retry policy allows it', async () => {
    let attempts = 0;
    const client = new PactmanClient(
      {
        apiKey: TEST_API_KEY,
        baseUrl: BASE_URL,
        timeoutMs: 10,
        retry: { maxRetries: 1, jitter: false, initialDelayMs: 1 },
        fetch: (url, init) => {
          attempts += 1;

          if (attempts > 1) {
            return Promise.resolve(
              new Response(JSON.stringify(envelope(nonprofitFixture())), {
                status: 200,
                headers: { 'content-type': 'application/json' },
              }),
            );
          }

          return hangingFetch()(url, init);
        },
      },
      createClock(),
    );

    const result = await client.nonprofits.check('411787097');

    expect(attempts).toBe(2);
    expect(result.nonprofit?.ein).toBe('411787097');
  });
});

describe('cancellation', () => {
  it('stops an in-flight request when the caller aborts', async () => {
    const controller = new AbortController();
    const client = new PactmanClient(
      {
        apiKey: TEST_API_KEY,
        baseUrl: BASE_URL,
        fetch: hangingFetch(() => {
          controller.abort();
        }),
        retry: { maxRetries: 3, jitter: false, initialDelayMs: 1 },
      },
      createClock(),
    );

    const error = await captureError<PactmanNetworkError>(
      client.nonprofits.check('411787097', { signal: controller.signal }),
    );

    expect(error).toBeInstanceOf(PactmanNetworkError);
    expect(error.message).toContain('aborted');
  });

  it('does not start a request when the signal is already aborted', async () => {
    let calls = 0;
    const client = new PactmanClient(
      {
        apiKey: TEST_API_KEY,
        baseUrl: BASE_URL,
        fetch: hangingFetch(() => {
          calls += 1;
        }),
      },
      createClock(),
    );

    await expect(
      client.nonprofits.check('411787097', { signal: AbortSignal.abort() }),
    ).rejects.toBeInstanceOf(PactmanNetworkError);
    expect(calls).toBe(0);
  });

  it('stops planned retries once the caller aborts', async () => {
    const controller = new AbortController();
    let calls = 0;
    const client = new PactmanClient(
      {
        apiKey: TEST_API_KEY,
        baseUrl: BASE_URL,
        retry: { maxRetries: 5, jitter: false, initialDelayMs: 1 },
        fetch: () => {
          calls += 1;

          if (calls === 2) {
            controller.abort();
          }

          return Promise.resolve(
            new Response(JSON.stringify({ code: 500 }), {
              status: 500,
              headers: { 'content-type': 'application/json' },
            }),
          );
        },
      },
      createClock(),
    );

    await client.nonprofits
      .check('411787097', { signal: controller.signal })
      .catch(() => undefined);

    expect(calls).toBe(2);
  });
});
