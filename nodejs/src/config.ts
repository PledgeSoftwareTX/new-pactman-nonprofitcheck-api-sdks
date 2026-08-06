/**
 * Client configuration: defaults, validation, and credential redaction.
 */

import {
  DEFAULT_ENVIRONMENT,
  baseUrlForEnvironment,
  supportedEnvironments,
  type PactmanEnvironment,
} from './environments.js';
import { PactmanConfigurationError } from './errors.js';
import { PACKAGE_NAME, VERSION } from './version.js';

/** The `fetch` signature this SDK depends on. */
export type FetchLike = (input: string, init: RequestInit) => Promise<Response>;

/** Retry policy. Applied per request, on top of the overall timeout. */
export interface RetryOptions {
  /**
   * Retries after the first attempt. `0` disables retrying.
   *
   * @defaultValue 2 (three attempts in total)
   */
  maxRetries?: number;
  /**
   * Delay before the first retry, in milliseconds. Subsequent delays grow by
   * `backoffFactor` and are randomized when `jitter` is on.
   *
   * @defaultValue 500
   */
  initialDelayMs?: number;
  /**
   * Ceiling for a single backoff delay, in milliseconds. A server-supplied
   * `Retry-After` is honored even when it exceeds this.
   *
   * @defaultValue 8000
   */
  maxDelayMs?: number;
  /** @defaultValue 2 */
  backoffFactor?: number;
  /**
   * Randomize each delay across `[0, computed]` (full jitter) so that clients
   * failing together do not retry in lockstep.
   *
   * @defaultValue true
   */
  jitter?: boolean;
  /**
   * HTTP statuses worth retrying. Authentication, authorization, validation and
   * not-found responses are never retried, whatever this contains.
   *
   * @defaultValue [429, 500, 502, 503, 504]
   */
  retryableStatuses?: number[];
  /**
   * Wait for the server's `Retry-After` before falling back to backoff.
   *
   * @defaultValue true
   */
  respectRetryAfter?: boolean;
}

/** Options accepted by the {@link import('./client.js').PactmanClient} constructor. */
export interface PactmanClientOptions {
  /**
   * Your Pactman API key. Load it from the environment or a secret manager;
   * never commit it, and never ship it to a browser.
   */
  apiKey: string;
  /**
   * Named Pactman environment.
   *
   * @defaultValue 'production'
   */
  environment?: PactmanEnvironment;
  /**
   * Explicit base URL, for a mock server, a proxy, or a host Pactman has given
   * you directly. Overrides `environment` when set.
   */
  baseUrl?: string;
  /**
   * Overall timeout per attempt, in milliseconds.
   *
   * @defaultValue 30000
   */
  timeoutMs?: number;
  /** Retry policy, or `false` to disable retrying entirely. */
  retry?: RetryOptions | false;
  /**
   * Optional client-side ceiling on outbound requests per second. Off by
   * default; the server's limits are authoritative and may change.
   */
  maxRequestsPerSecond?: number;
  /** Extra headers sent with every request. Cannot override `Authorization`. */
  defaultHeaders?: Record<string, string>;
  /**
   * `fetch` implementation to use.
   *
   * @defaultValue the runtime's global `fetch`
   */
  fetch?: FetchLike;
}

/** Fully-resolved retry policy. */
export type ResolvedRetryOptions = Required<RetryOptions>;

/** Fully-resolved configuration, with the API key held separately. */
export interface ResolvedConfig {
  baseUrl: string;
  environment: PactmanEnvironment | null;
  timeoutMs: number;
  retry: ResolvedRetryOptions;
  maxRequestsPerSecond: number | null;
  defaultHeaders: Record<string, string>;
  userAgent: string;
  fetch: FetchLike;
}

/** Default overall timeout per attempt, in milliseconds. */
export const DEFAULT_TIMEOUT_MS = 30_000;

const DEFAULT_RETRY: ResolvedRetryOptions = {
  maxRetries: 2,
  initialDelayMs: 500,
  maxDelayMs: 8_000,
  backoffFactor: 2,
  jitter: true,
  retryableStatuses: [429, 500, 502, 503, 504],
  respectRetryAfter: true,
};

/** Statuses that are never retried, regardless of `retryableStatuses`. */
const NEVER_RETRY_STATUSES = new Set([400, 401, 403, 404]);

/**
 * Validates and resolves constructor options.
 *
 * @throws {PactmanConfigurationError} for a missing or blank API key, an
 * unknown environment, a malformed base URL, or nonsensical numeric options.
 */
export function resolveConfig(options: PactmanClientOptions): {
  apiKey: string;
  config: ResolvedConfig;
} {
  if (options === null || typeof options !== 'object') {
    throw new PactmanConfigurationError(
      'PactmanClient requires an options object containing an apiKey.',
    );
  }

  const apiKey = validateApiKey(options.apiKey);
  const baseUrl = resolveBaseUrl(options);
  const timeoutMs = resolveTimeout(options.timeoutMs);
  const fetchImpl = resolveFetch(options.fetch);

  return {
    apiKey,
    config: {
      baseUrl,
      environment: options.baseUrl ? null : (options.environment ?? DEFAULT_ENVIRONMENT),
      timeoutMs,
      retry: resolveRetry(options.retry),
      maxRequestsPerSecond: resolveRequestsPerSecond(options.maxRequestsPerSecond),
      defaultHeaders: { ...(options.defaultHeaders ?? {}) },
      userAgent: buildUserAgent(),
      fetch: fetchImpl,
    },
  };
}

/** True when a status may be retried under `retry`. */
export function isRetryableStatus(status: number, retry: ResolvedRetryOptions): boolean {
  if (NEVER_RETRY_STATUSES.has(status)) {
    return false;
  }

  return retry.retryableStatuses.includes(status);
}

/** `pactman-nonprofit-check-plus/<version> (node/<version>; <platform>)` */
export function buildUserAgent(): string {
  const name = PACKAGE_NAME.replace('@', '').replace('/', '-');
  const runtime =
    typeof process !== 'undefined' && process.versions?.node
      ? ` (node/${process.versions.node}; ${process.platform})`
      : '';

  return `${name}/${VERSION}${runtime}`;
}

function validateApiKey(apiKey: unknown): string {
  if (apiKey === null || apiKey === undefined) {
    throw new PactmanConfigurationError(
      'A Pactman API key is required. Pass `apiKey`, for example from process.env.PACTMAN_API_KEY.',
    );
  }

  if (typeof apiKey !== 'string') {
    throw new PactmanConfigurationError(
      `The Pactman API key must be a string, received ${typeof apiKey}.`,
    );
  }

  if (apiKey.trim() === '') {
    throw new PactmanConfigurationError(
      'The Pactman API key is empty. Check that the environment variable holding it is set.',
    );
  }

  return apiKey.trim();
}

function resolveBaseUrl(options: PactmanClientOptions): string {
  if (options.baseUrl !== undefined) {
    return validateBaseUrl(options.baseUrl);
  }

  const environment = options.environment ?? DEFAULT_ENVIRONMENT;

  if (!supportedEnvironments().includes(environment)) {
    throw new PactmanConfigurationError(
      `Unknown environment "${String(environment)}". Supported: ${supportedEnvironments().join(', ')}. ` +
        'Use `baseUrl` to target a host that is not a named environment.',
    );
  }

  return baseUrlForEnvironment(environment);
}

function validateBaseUrl(baseUrl: unknown): string {
  if (typeof baseUrl !== 'string' || baseUrl.trim() === '') {
    throw new PactmanConfigurationError('`baseUrl` must be a non-empty URL string.');
  }

  let parsed: URL;

  try {
    parsed = new URL(baseUrl.trim());
  } catch {
    throw new PactmanConfigurationError(
      `\`baseUrl\` is not a valid URL: "${baseUrl}". Expected something like https://entities.pactman.org.`,
    );
  }

  if (parsed.protocol !== 'https:' && parsed.protocol !== 'http:') {
    throw new PactmanConfigurationError(
      `\`baseUrl\` must use http or https, received "${parsed.protocol}".`,
    );
  }

  return parsed.origin + parsed.pathname.replace(/\/+$/, '');
}

function resolveTimeout(timeoutMs: unknown): number {
  if (timeoutMs === undefined) {
    return DEFAULT_TIMEOUT_MS;
  }

  if (typeof timeoutMs !== 'number' || !Number.isFinite(timeoutMs) || timeoutMs <= 0) {
    throw new PactmanConfigurationError(
      '`timeoutMs` must be a finite number greater than zero. There is no way to disable the timeout.',
    );
  }

  return timeoutMs;
}

function resolveRetry(retry: RetryOptions | false | undefined): ResolvedRetryOptions {
  if (retry === false) {
    return { ...DEFAULT_RETRY, maxRetries: 0 };
  }

  if (retry === undefined) {
    return { ...DEFAULT_RETRY };
  }

  const resolved: ResolvedRetryOptions = {
    ...DEFAULT_RETRY,
    ...retry,
    retryableStatuses: retry.retryableStatuses
      ? [...retry.retryableStatuses]
      : [...DEFAULT_RETRY.retryableStatuses],
  };

  if (!Number.isInteger(resolved.maxRetries) || resolved.maxRetries < 0) {
    throw new PactmanConfigurationError('`retry.maxRetries` must be an integer of 0 or more.');
  }

  if (!Number.isFinite(resolved.initialDelayMs) || resolved.initialDelayMs < 0) {
    throw new PactmanConfigurationError('`retry.initialDelayMs` must be 0 or more.');
  }

  if (!Number.isFinite(resolved.maxDelayMs) || resolved.maxDelayMs < 0) {
    throw new PactmanConfigurationError('`retry.maxDelayMs` must be 0 or more.');
  }

  if (!Number.isFinite(resolved.backoffFactor) || resolved.backoffFactor < 1) {
    throw new PactmanConfigurationError('`retry.backoffFactor` must be 1 or more.');
  }

  return resolved;
}

function resolveRequestsPerSecond(value: unknown): number | null {
  if (value === undefined || value === null) {
    return null;
  }

  if (typeof value !== 'number' || !Number.isFinite(value) || value <= 0) {
    throw new PactmanConfigurationError(
      '`maxRequestsPerSecond` must be a finite number greater than zero, or omitted.',
    );
  }

  return value;
}

function resolveFetch(fetchImpl: FetchLike | undefined): FetchLike {
  if (fetchImpl) {
    return fetchImpl;
  }

  if (typeof globalThis.fetch === 'function') {
    return globalThis.fetch.bind(globalThis) as FetchLike;
  }

  throw new PactmanConfigurationError(
    'No global fetch is available. Use Node 18 or newer, or pass a `fetch` implementation.',
  );
}
