import { describe, expect, it } from 'vitest';
import { inspect } from 'node:util';
import { PactmanClient } from '../src/client.js';
import {
  PactmanApiError,
  PactmanAuthenticationError,
  PactmanAuthorizationError,
  PactmanBadRequestError,
  PactmanError,
  PactmanErrorCategory,
  PactmanNetworkError,
  PactmanNotFoundError,
  PactmanRateLimitError,
  PactmanServerError,
  PactmanTimeoutError,
  isPactmanError,
} from '../src/errors.js';
import { captureError, createClock, createFetchMock, TEST_API_KEY, type Stub } from './helpers.js';

const BASE_URL = 'http://mock.test';

function checkWith(stub: Stub, timeoutMs = 30_000): Promise<unknown> {
  const mock = createFetchMock([stub]);
  const client = new PactmanClient(
    { apiKey: TEST_API_KEY, baseUrl: BASE_URL, fetch: mock.fetch, retry: false, timeoutMs },
    createClock(),
  );

  return client.nonprofits.check('411787097');
}

describe('status to error-category mapping', () => {
  it.each([
    [400, PactmanBadRequestError, PactmanErrorCategory.BadRequest],
    [401, PactmanAuthenticationError, PactmanErrorCategory.Authentication],
    [403, PactmanAuthorizationError, PactmanErrorCategory.Authorization],
    [404, PactmanNotFoundError, PactmanErrorCategory.NotFound],
    [429, PactmanRateLimitError, PactmanErrorCategory.RateLimit],
    [500, PactmanServerError, PactmanErrorCategory.Server],
    [503, PactmanServerError, PactmanErrorCategory.Server],
  ])('maps HTTP %i to the documented category', async (status, ErrorClass, category) => {
    const error = await captureError<PactmanApiError>(
      checkWith({ status, body: { code: status, message: 'failed', errors: null, data: null } }),
    );

    expect(error).toBeInstanceOf(ErrorClass);
    expect(error.category).toBe(category);
    expect(error.origin).toBe('api');
    expect(error.status).toBe(status);
  });

  it('falls back to a general API error for an unexpected status', async () => {
    const error = await captureError<PactmanApiError>(
      checkWith({ status: 418, body: { message: "I'm a teapot" } }),
    );

    expect(error).toBeInstanceOf(PactmanApiError);
    expect(error.category).toBe(PactmanErrorCategory.Api);
    expect(error.status).toBe(418);
    expect(error.apiMessage).toBe("I'm a teapot");
  });

  it('keeps response metadata when the body cannot be deserialized', async () => {
    const error = await captureError<PactmanApiError>(
      checkWith({
        status: 502,
        bodyText: '<html>gateway error</html>',
        headers: { 'content-type': 'text/html', 'x-request-id': 'req-html-1' },
      }),
    );

    expect(error).toBeInstanceOf(PactmanServerError);
    expect(error.status).toBe(502);
    expect(error.requestId).toBe('req-html-1');
    expect(error.raw).toBe('<html>gateway error</html>');
  });
});

describe('error detail', () => {
  it('exposes Retry-After on a 429', async () => {
    const error = await captureError<PactmanRateLimitError>(
      checkWith({
        status: 429,
        body: { code: 429, message: 'Too Many Requests' },
        headers: { 'retry-after': '12' },
      }),
    );

    expect(error.category).toBe(PactmanErrorCategory.RateLimit);
    expect(error.retryAfterSeconds).toBe(12);
  });

  it('retains the request ID on a server error', async () => {
    const error = await captureError<PactmanServerError>(
      checkWith({
        status: 500,
        body: { code: 500, message: 'Internal Server Error' },
        headers: { 'x-request-id': 'req-abc-123' },
      }),
    );

    expect(error.requestId).toBe('req-abc-123');
  });

  it('surfaces the API reason list without string parsing', async () => {
    const error = await captureError<PactmanBadRequestError>(
      checkWith({
        status: 400,
        body: {
          code: 400,
          message: 'Bad Request',
          errors: [
            { resource: 'nonprofitcheck', reason: 'Invalid EIN format', code: 400 },
            { resource: 'nonprofitcheck', reason: 'EIN must contain 9 digits' },
          ],
          data: null,
        },
      }),
    );

    expect(error.apiErrors).toHaveLength(2);
    expect(error.apiErrors[0]?.reason).toBe('Invalid EIN format');
    expect(error.apiCode).toBe(400);
  });

  it('reports transport failures as network errors', async () => {
    const error = await captureError<PactmanNetworkError>(checkWith(new TypeError('fetch failed')));

    expect(error).toBeInstanceOf(PactmanNetworkError);
    expect(error.category).toBe(PactmanErrorCategory.Network);
    expect(error.origin).toBe('local');
  });

  it('distinguishes local errors from API errors', async () => {
    const mock = createFetchMock([{ status: 400, body: { message: 'Bad Request' } }]);
    const client = new PactmanClient({
      apiKey: TEST_API_KEY,
      baseUrl: BASE_URL,
      fetch: mock.fetch,
      retry: false,
    });

    const local = await captureError<PactmanError>(client.nonprofits.check('bad-ein'));
    const remote = await captureError<PactmanError>(client.nonprofits.check('411787097'));

    expect(local.origin).toBe('local');
    expect(local.category).toBe(PactmanErrorCategory.Validation);
    expect(remote.origin).toBe('api');
    expect(isPactmanError(local)).toBe(true);
    expect(isPactmanError(remote)).toBe(true);
  });

  it('is catchable through the common base class', async () => {
    await expect(checkWith({ status: 401, body: {} })).rejects.toBeInstanceOf(PactmanError);
  });
});

describe('credential safety in diagnostics', () => {
  const stubs: Array<[string, Stub]> = [
    ['401', { status: 401, body: { code: 401, message: 'Unauthorized' } }],
    ['429', { status: 429, body: { code: 429 }, headers: { 'retry-after': '3' } }],
    ['500', { status: 500, body: { code: 500 } }],
    ['network failure', new TypeError('fetch failed')],
  ];

  it.each(stubs)('keeps the API key out of a %s error', async (_label, stub) => {
    const error = await captureError<PactmanError>(checkWith(stub));

    const surfaces = [
      error.message,
      String(error),
      error.stack ?? '',
      JSON.stringify(error.toJSON()),
      JSON.stringify(error),
      inspect(error, { depth: 6 }),
    ];

    for (const surface of surfaces) {
      expect(surface).not.toContain(TEST_API_KEY);
    }
  });

  it('keeps the API key out of a timeout error', async () => {
    const client = new PactmanClient(
      {
        apiKey: TEST_API_KEY,
        baseUrl: BASE_URL,
        retry: false,
        timeoutMs: 5,
        fetch: (_url, init) =>
          new Promise((_resolve, reject) => {
            init.signal?.addEventListener('abort', () => {
              reject(new DOMException('This operation was aborted', 'AbortError'));
            });
          }),
      },
      createClock(),
    );

    const error = await captureError<PactmanTimeoutError>(client.nonprofits.check('411787097'));

    expect(error).toBeInstanceOf(PactmanTimeoutError);
    expect(inspect(error, { depth: 6 })).not.toContain(TEST_API_KEY);
  });
});
