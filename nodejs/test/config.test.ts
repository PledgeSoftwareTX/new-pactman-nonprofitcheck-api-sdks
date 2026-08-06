import { describe, expect, it } from 'vitest';
import { inspect } from 'node:util';
import { readFileSync } from 'node:fs';
import { PactmanClient } from '../src/client.js';
import { PactmanConfigurationError, PactmanErrorCategory } from '../src/errors.js';
import {
  DEFAULT_ENVIRONMENT,
  PactmanEnvironment,
  baseUrlForEnvironment,
  supportedEnvironments,
} from '../src/environments.js';
import { PACKAGE_NAME, VERSION } from '../src/version.js';
import { buildUserAgent } from '../src/config.js';
import { createFetchMock, envelope, nonprofitFixture, TEST_API_KEY } from './helpers.js';

describe('client construction', () => {
  it('creates a client from the minimum documented configuration', () => {
    const client = new PactmanClient({ apiKey: TEST_API_KEY });

    expect(client.baseUrl).toBe(baseUrlForEnvironment(PactmanEnvironment.Production));
    expect(client.environment).toBe(DEFAULT_ENVIRONMENT);
    expect(client.timeoutMs).toBe(30_000);
  });

  it.each([
    ['missing', undefined],
    ['empty', ''],
    ['whitespace-only', '   '],
    ['a number', 42],
  ])('rejects a %s API key locally', (_label, apiKey) => {
    expect(() => new PactmanClient({ apiKey: apiKey as string })).toThrowError(
      PactmanConfigurationError,
    );
  });

  it('reports a configuration category on a bad API key', () => {
    try {
      new PactmanClient({ apiKey: '' });
      expect.unreachable('constructing with an empty key should throw');
    } catch (error) {
      expect(error).toBeInstanceOf(PactmanConfigurationError);
      expect((error as PactmanConfigurationError).category).toBe(
        PactmanErrorCategory.Configuration,
      );
      expect((error as PactmanConfigurationError).origin).toBe('local');
    }
  });

  it('sends no request when the API key is empty', async () => {
    const mock = createFetchMock([{ body: envelope(nonprofitFixture()) }]);

    expect(() => new PactmanClient({ apiKey: '', fetch: mock.fetch })).toThrow();
    expect(mock.requests).toHaveLength(0);
  });
});

describe('environment and base-URL selection', () => {
  it('resolves a URL for every named environment', () => {
    const environments = supportedEnvironments();

    expect(environments).toContain(PactmanEnvironment.Production);

    for (const environment of environments) {
      const client = new PactmanClient({ apiKey: TEST_API_KEY, environment });

      expect(() => new URL(client.baseUrl)).not.toThrow();
      expect(client.baseUrl.startsWith('https://')).toBe(true);
    }
  });

  it('exposes production only — internal QA and sandbox hosts are not selectable', () => {
    expect(supportedEnvironments()).toEqual([PactmanEnvironment.Production]);

    for (const environment of supportedEnvironments()) {
      expect(baseUrlForEnvironment(environment)).not.toMatch(/sandbox|sit|qa|hllc\.mobi/i);
    }
  });

  it('accepts a custom base URL for a local mock server', () => {
    const client = new PactmanClient({
      apiKey: TEST_API_KEY,
      baseUrl: 'http://127.0.0.1:4010',
    });

    expect(client.baseUrl).toBe('http://127.0.0.1:4010');
    expect(client.environment).toBeNull();
  });

  it('strips a trailing slash from a custom base URL', () => {
    const client = new PactmanClient({ apiKey: TEST_API_KEY, baseUrl: 'https://example.test/' });

    expect(client.baseUrl).toBe('https://example.test');
  });

  it.each([
    ['not a url', 'entities.pactman.org'],
    ['empty', ''],
    ['an unsupported scheme', 'ftp://entities.pactman.org'],
  ])('rejects %s base URLs locally', (_label, baseUrl) => {
    expect(() => new PactmanClient({ apiKey: TEST_API_KEY, baseUrl })).toThrowError(
      PactmanConfigurationError,
    );
  });

  it('rejects an unknown environment name', () => {
    expect(
      () =>
        new PactmanClient({
          apiKey: TEST_API_KEY,
          environment: 'staging' as PactmanEnvironment,
        }),
    ).toThrowError(PactmanConfigurationError);
  });
});

describe('option validation', () => {
  it.each([
    ['a zero timeout', { timeoutMs: 0 }],
    ['a negative timeout', { timeoutMs: -1 }],
    ['an infinite timeout', { timeoutMs: Number.POSITIVE_INFINITY }],
    ['a negative retry count', { retry: { maxRetries: -1 } }],
    ['a fractional retry count', { retry: { maxRetries: 1.5 } }],
    ['a backoff factor below 1', { retry: { backoffFactor: 0.5 } }],
    ['a zero request-per-second cap', { maxRequestsPerSecond: 0 }],
  ])('rejects %s', (_label, overrides) => {
    expect(() => new PactmanClient({ apiKey: TEST_API_KEY, ...overrides })).toThrowError(
      PactmanConfigurationError,
    );
  });

  it('honours an explicit timeout override', () => {
    const client = new PactmanClient({ apiKey: TEST_API_KEY, timeoutMs: 1_500 });

    expect(client.timeoutMs).toBe(1_500);
  });
});

describe('credential redaction', () => {
  const client = new PactmanClient({ apiKey: TEST_API_KEY });

  it('keeps the key out of JSON serialization', () => {
    const serialized = JSON.stringify(client);

    expect(serialized).not.toContain(TEST_API_KEY);
    expect(serialized).toContain('[redacted]');
  });

  it('keeps the key out of util.inspect and console output', () => {
    expect(inspect(client, { depth: 5 })).not.toContain(TEST_API_KEY);
  });

  it('keeps the key out of toString', () => {
    expect(String(client)).not.toContain(TEST_API_KEY);
  });

  it('does not expose the key as an enumerable property', () => {
    expect(Object.values(client).join(' ')).not.toContain(TEST_API_KEY);
    expect(Object.keys(client)).not.toContain('apiKey');
  });
});

describe('user agent', () => {
  it('identifies the SDK language and version', () => {
    const userAgent = buildUserAgent();

    expect(userAgent).toContain(PACKAGE_NAME.replace('@', '').replace('/', '-'));
    expect(userAgent).toContain(VERSION);
    expect(userAgent).toContain('node/');
  });

  it('matches the package name declared in package.json', () => {
    const pkg = JSON.parse(readFileSync(new URL('../package.json', import.meta.url), 'utf8')) as {
      name: string;
    };

    expect(PACKAGE_NAME).toBe(pkg.name);
  });

  it('matches the version declared in package.json', () => {
    const pkg = JSON.parse(
      readFileSync(new URL('../package.json', import.meta.url), 'utf8'),
    ) as { version: string };

    expect(VERSION).toBe(pkg.version);
  });
});
