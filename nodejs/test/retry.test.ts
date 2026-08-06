import { describe, expect, it } from 'vitest';
import { PactmanClient } from '../src/client.js';
import {
  PactmanAuthenticationError,
  PactmanRateLimitError,
  PactmanServerError,
  PactmanValidationError,
} from '../src/errors.js';
import { computeRetryDelay, readRetryAfter } from '../src/http.js';
import type { ResolvedRetryOptions } from '../src/config.js';
import {
  captureError,
  createClock,
  createFetchMock,
  envelope,
  nonprofitFixture,
  TEST_API_KEY,
  type ClockMock,
  type Stub,
} from './helpers.js';

const BASE_URL = 'http://mock.test';

function build(stubs: Stub[], overrides: Record<string, unknown> = {}, random = 1) {
  const mock = createFetchMock(stubs);
  const clock: ClockMock = createClock(random);
  const client = new PactmanClient(
    { apiKey: TEST_API_KEY, baseUrl: BASE_URL, fetch: mock.fetch, ...overrides },
    clock,
  );

  return { mock, clock, client };
}

const RETRY_DEFAULTS: ResolvedRetryOptions = {
  maxRetries: 2,
  initialDelayMs: 500,
  maxDelayMs: 8_000,
  backoffFactor: 2,
  jitter: false,
  retryableStatuses: [429, 500, 502, 503, 504],
  respectRetryAfter: true,
};

describe('automatic retries', () => {
  it('succeeds after a temporary failure and records the expected attempt count', async () => {
    const { mock, client } = build([
      { status: 503, body: { code: 503, message: 'Service Unavailable' } },
      { status: 200, body: envelope(nonprofitFixture()) },
    ]);

    const result = await client.nonprofits.check('411787097');

    expect(mock.requests).toHaveLength(2);
    expect(result.nonprofit?.ein).toBe('411787097');
  });

  it('never exceeds the configured maximum attempt count', async () => {
    const { mock, client } = build([{ status: 500, body: { code: 500 } }], {
      retry: { maxRetries: 3, jitter: false },
    });

    const error = await captureError<PactmanServerError>(client.nonprofits.check('411787097'));

    expect(mock.requests).toHaveLength(4);
    expect(error).toBeInstanceOf(PactmanServerError);
    expect(error.attempts).toBe(4);
  });

  it('makes a single attempt when retries are disabled', async () => {
    const { mock, client } = build([{ status: 500, body: { code: 500 } }], { retry: false });

    await client.nonprofits.check('411787097').catch(() => undefined);

    expect(mock.requests).toHaveLength(1);
  });

  it('retries temporary network failures', async () => {
    const { mock, client } = build([
      new TypeError('fetch failed'),
      { status: 200, body: envelope(nonprofitFixture()) },
    ]);

    await client.nonprofits.check('411787097');

    expect(mock.requests).toHaveLength(2);
  });

  it.each([
    ['401 authentication', 401],
    ['403 authorization', 403],
    ['400 validation', 400],
    ['404 not found', 404],
  ])('does not retry a %s response', async (_label, status) => {
    const { mock, client } = build([{ status, body: { code: status } }]);

    await client.nonprofits.check('411787097').catch(() => undefined);

    expect(mock.requests).toHaveLength(1);
  });

  it('surfaces a 401 as an authentication error on the first attempt', async () => {
    const { client } = build([{ status: 401, body: { code: 401 } }]);

    const error = await captureError<PactmanAuthenticationError>(
      client.nonprofits.check('411787097'),
    );

    expect(error).toBeInstanceOf(PactmanAuthenticationError);
    expect(error.attempts).toBe(1);
  });

  it('does not retry local validation errors', async () => {
    const { mock, client } = build([{ status: 200, body: envelope(nonprofitFixture()) }]);

    await expect(client.nonprofits.check('bad')).rejects.toBeInstanceOf(PactmanValidationError);
    expect(mock.requests).toHaveLength(0);
  });

  it('applies exponential backoff with a deterministic clock', async () => {
    const { clock, client } = build([{ status: 500, body: { code: 500 } }], {
      retry: { maxRetries: 3, jitter: false, initialDelayMs: 100, backoffFactor: 2 },
    });

    await client.nonprofits.check('411787097').catch(() => undefined);

    expect(clock.delays).toEqual([100, 200, 400]);
  });

  it('applies full jitter across the backoff window', async () => {
    const { clock, client } = build(
      [{ status: 500, body: { code: 500 } }],
      { retry: { maxRetries: 2, jitter: true, initialDelayMs: 100, backoffFactor: 2 } },
      0.5,
    );

    await client.nonprofits.check('411787097').catch(() => undefined);

    expect(clock.delays).toEqual([50, 100]);
  });

  it('caps a single backoff delay at maxDelayMs', async () => {
    const { clock, client } = build([{ status: 500, body: { code: 500 } }], {
      retry: { maxRetries: 3, jitter: false, initialDelayMs: 1_000, backoffFactor: 10, maxDelayMs: 2_000 },
    });

    await client.nonprofits.check('411787097').catch(() => undefined);

    expect(clock.delays).toEqual([1_000, 2_000, 2_000]);
  });

  it('accepts a per-request retry override', async () => {
    const { mock, client } = build([{ status: 500, body: { code: 500 } }], { retry: false });

    await client.nonprofits.check('411787097', { retry: { maxRetries: 1 } }).catch(() => undefined);

    expect(mock.requests).toHaveLength(2);
  });
});

describe('rate limiting', () => {
  it('maps 429 to the rate-limit error and exposes Retry-After', async () => {
    const { client } = build([{ status: 429, body: { code: 429 }, headers: { 'retry-after': '5' } }], {
      retry: false,
    });

    const error = await captureError<PactmanRateLimitError>(client.nonprofits.check('411787097'));

    expect(error).toBeInstanceOf(PactmanRateLimitError);
    expect(error.retryAfterSeconds).toBe(5);
  });

  it('waits for the server Retry-After before falling back to backoff', async () => {
    const { clock, client } = build(
      [
        { status: 429, body: { code: 429 }, headers: { 'retry-after': '7' } },
        { status: 200, body: envelope(nonprofitFixture()) },
      ],
      { retry: { maxRetries: 2, jitter: false, initialDelayMs: 100 } },
    );

    await client.nonprofits.check('411787097');

    expect(clock.delays).toEqual([7_000]);
  });

  it('ignores Retry-After when the caller opts out', async () => {
    const { clock, client } = build(
      [
        { status: 429, body: { code: 429 }, headers: { 'retry-after': '7' } },
        { status: 200, body: envelope(nonprofitFixture()) },
      ],
      { retry: { maxRetries: 2, jitter: false, initialDelayMs: 250, respectRetryAfter: false } },
    );

    await client.nonprofits.check('411787097');

    expect(clock.delays).toEqual([250]);
  });

  it('reads Retry-After given as an HTTP date', () => {
    const now = Date.UTC(2026, 0, 1, 12, 0, 0);
    const headers = new Headers({ 'retry-after': new Date(now + 4_000).toUTCString() });

    expect(readRetryAfter(headers, now)).toBe(4);
    expect(computeRetryDelay(1, RETRY_DEFAULTS, 4, () => 1)).toBe(4_000);
  });

  it('ignores an unparseable Retry-After', () => {
    expect(readRetryAfter(new Headers({ 'retry-after': 'soon' }))).toBeNull();
    expect(readRetryAfter(new Headers())).toBeNull();
  });

  it('spaces requests when a client-side limit is configured', async () => {
    const { clock, client } = build(
      [{ status: 200, body: envelope(nonprofitFixture()) }],
      { maxRequestsPerSecond: 2 },
    );

    await client.nonprofits.check('411787097');
    await client.nonprofits.check('411787097');
    await client.nonprofits.check('411787097');

    // Two requests per second means a 500ms slot each. The fake clock records
    // the wait without advancing wall time, so the schedule accumulates. Real
    // milliseconds still elapse between calls, so assert the window, not exact
    // values.
    expect(clock.delays).toHaveLength(2);
    expect(clock.delays[0]).toBeGreaterThan(400);
    expect(clock.delays[0]).toBeLessThanOrEqual(500);
    expect(clock.delays[1]).toBeGreaterThan(900);
    expect(clock.delays[1]).toBeLessThanOrEqual(1_000);
  });

  it('does not throttle when no client-side limit is set', async () => {
    const { clock, client } = build([{ status: 200, body: envelope(nonprofitFixture()) }]);

    await client.nonprofits.check('411787097');
    await client.nonprofits.check('411787097');

    expect(clock.delays).toEqual([]);
  });
});

describe('computeRetryDelay', () => {
  it('prefers a valid Retry-After over computed backoff', () => {
    expect(computeRetryDelay(1, RETRY_DEFAULTS, 3)).toBe(3_000);
  });

  it('falls back to backoff when Retry-After is absent', () => {
    expect(computeRetryDelay(1, RETRY_DEFAULTS, null)).toBe(500);
    expect(computeRetryDelay(3, RETRY_DEFAULTS, null)).toBe(2_000);
  });
});
