/**
 * HTTP transport: authentication headers, timeouts, cancellation, retries with
 * jittered backoff, `Retry-After` handling, and mapping responses to the error
 * taxonomy.
 *
 * The API key is written into the `Authorization` header at send time and is
 * never stored on a request record, an error, or any diagnostic output.
 */

import {
  isRetryableStatus,
  type ResolvedConfig,
  type ResolvedRetryOptions,
  type RetryOptions,
} from './config.js';
import {
  PactmanNetworkError,
  PactmanTimeoutError,
  errorFromStatus,
  type PactmanApiErrorInit,
} from './errors.js';
import type { ApiEnvelope, ApiErrorDetail } from './types.js';

/** Per-request overrides accepted by every public method. */
export interface RequestOptions {
  /** Overrides the client's timeout for this request. */
  timeoutMs?: number;
  /** Overrides the client's retry policy for this request. */
  retry?: RetryOptions | false;
  /** Aborts the request and any planned retries. */
  signal?: AbortSignal;
  /** Extra headers for this request. Cannot override `Authorization`. */
  headers?: Record<string, string>;
}

/** Hooks the test suite substitutes for real time. Not part of the public API. */
export interface TransportHooks {
  /** Resolves after `ms`, or rejects if `signal` aborts first. */
  sleep?: (ms: number, signal?: AbortSignal) => Promise<void>;
  /** Returns a value in `[0, 1)`. Used for backoff jitter. */
  random?: () => number;
}

/** A parsed HTTP response plus the metadata callers need. */
export interface TransportResponse<TData> {
  status: number;
  requestId: string | null;
  body: ApiEnvelope<TData>;
  attempts: number;
}

interface SendParams {
  method: 'GET' | 'POST';
  path: string;
  body?: unknown;
  options?: RequestOptions;
}

/** Issues authenticated requests against the Pactman API. */
export class Transport {
  readonly #apiKey: string;
  readonly #config: ResolvedConfig;
  readonly #hooks: Required<TransportHooks>;
  #nextRequestAt = 0;

  constructor(apiKey: string, config: ResolvedConfig, hooks: TransportHooks = {}) {
    this.#apiKey = apiKey;
    this.#config = config;
    this.#hooks = {
      sleep: hooks.sleep ?? defaultSleep,
      random: hooks.random ?? Math.random,
    };
  }

  async send<TData>({ method, path, body, options }: SendParams): Promise<TransportResponse<TData>> {
    const retry = resolveRequestRetry(this.#config.retry, options?.retry);
    const timeoutMs = options?.timeoutMs ?? this.#config.timeoutMs;
    const url = `${this.#config.baseUrl}${path}`;
    const headers = this.#buildHeaders(options?.headers, body !== undefined);
    const payload = body === undefined ? undefined : JSON.stringify(body);

    let attempt = 0;

    for (;;) {
      attempt += 1;
      throwIfAborted(options?.signal);
      await this.#throttle(options?.signal);

      const outcome = await this.#attempt<TData>({
        url,
        method,
        headers,
        payload,
        timeoutMs,
        attempt,
        signal: options?.signal,
      });

      if (outcome.kind === 'response') {
        const { response, parsed } = outcome;

        if (response.ok) {
          return {
            status: response.status,
            requestId: readRequestId(response.headers),
            body: parsed as ApiEnvelope<TData>,
            attempts: attempt,
          };
        }

        const retryAfterSeconds = readRetryAfter(response.headers);
        const apiError = errorFromStatus(
          buildApiErrorInit(response.status, parsed, readRequestId(response.headers), {
            retryAfterSeconds,
            attempts: attempt,
          }),
        );

        if (attempt > retry.maxRetries || !isRetryableStatus(response.status, retry)) {
          throw apiError;
        }

        await this.#waitBeforeRetry(attempt, retry, retryAfterSeconds, options?.signal);
        continue;
      }

      // A timeout or transport failure.
      if (attempt > retry.maxRetries || outcome.kind === 'aborted') {
        throw outcome.error;
      }

      await this.#waitBeforeRetry(attempt, retry, null, options?.signal);
    }
  }

  #buildHeaders(perRequest: Record<string, string> | undefined, hasBody: boolean): Headers {
    const headers = new Headers({
      ...this.#config.defaultHeaders,
      ...(perRequest ?? {}),
    });

    headers.set('Accept', 'application/json');
    headers.set('User-Agent', this.#config.userAgent);
    headers.set('Authorization', `Bearer ${this.#apiKey}`);

    if (hasBody) {
      headers.set('Content-Type', 'application/json');
    }

    return headers;
  }

  /** Spaces requests when `maxRequestsPerSecond` is configured. */
  async #throttle(signal?: AbortSignal): Promise<void> {
    const limit = this.#config.maxRequestsPerSecond;

    if (limit === null) {
      return;
    }

    const intervalMs = 1000 / limit;
    const now = Date.now();
    const scheduledAt = Math.max(now, this.#nextRequestAt);
    this.#nextRequestAt = scheduledAt + intervalMs;

    if (scheduledAt > now) {
      await this.#hooks.sleep(scheduledAt - now, signal);
    }
  }

  async #attempt<TData>(params: {
    url: string;
    method: string;
    headers: Headers;
    payload: string | undefined;
    timeoutMs: number;
    attempt: number;
    signal?: AbortSignal;
  }): Promise<AttemptOutcome<TData>> {
    const controller = new AbortController();
    const onCallerAbort = () => controller.abort(params.signal?.reason);
    let timedOut = false;

    const timer = setTimeout(() => {
      timedOut = true;
      controller.abort();
    }, params.timeoutMs);

    params.signal?.addEventListener('abort', onCallerAbort, { once: true });

    try {
      const response = await this.#config.fetch(params.url, {
        method: params.method,
        headers: params.headers,
        body: params.payload,
        signal: controller.signal,
      });

      const parsed = await parseBody<TData>(response);

      return { kind: 'response', response, parsed };
    } catch (cause) {
      if (timedOut) {
        return {
          kind: 'failed',
          error: new PactmanTimeoutError(
            `The request timed out after ${params.timeoutMs}ms.`,
            params.timeoutMs,
            params.attempt,
            { cause },
          ),
        };
      }

      if (params.signal?.aborted) {
        return {
          kind: 'aborted',
          error: new PactmanNetworkError('The request was aborted by the caller.', params.attempt, {
            cause,
          }),
        };
      }

      return {
        kind: 'failed',
        error: new PactmanNetworkError(
          `The request to the Pactman API failed: ${describe(cause)}`,
          params.attempt,
          { cause },
        ),
      };
    } finally {
      clearTimeout(timer);
      params.signal?.removeEventListener('abort', onCallerAbort);
    }
  }

  async #waitBeforeRetry(
    attempt: number,
    retry: ResolvedRetryOptions,
    retryAfterSeconds: number | null,
    signal?: AbortSignal,
  ): Promise<void> {
    const delayMs = computeRetryDelay(attempt, retry, retryAfterSeconds, this.#hooks.random);
    await this.#hooks.sleep(delayMs, signal);
    throwIfAborted(signal);
  }
}

type AttemptOutcome<TData> =
  | { kind: 'response'; response: Response; parsed: ApiEnvelope<TData> | string | null }
  | { kind: 'failed'; error: PactmanTimeoutError | PactmanNetworkError }
  | { kind: 'aborted'; error: PactmanNetworkError };

/**
 * Delay before the next attempt.
 *
 * A valid `Retry-After` wins outright. Otherwise the delay grows exponentially
 * from `initialDelayMs`, is capped at `maxDelayMs`, and — with jitter on — is
 * randomized across the whole range so concurrent clients spread out.
 */
export function computeRetryDelay(
  attempt: number,
  retry: ResolvedRetryOptions,
  retryAfterSeconds: number | null,
  random: () => number = Math.random,
): number {
  if (retry.respectRetryAfter && retryAfterSeconds !== null && retryAfterSeconds >= 0) {
    return Math.round(retryAfterSeconds * 1000);
  }

  const exponential = retry.initialDelayMs * retry.backoffFactor ** (attempt - 1);
  const capped = Math.min(exponential, retry.maxDelayMs);

  return Math.round(retry.jitter ? random() * capped : capped);
}

/** Reads `Retry-After` as either a delay in seconds or an HTTP date. */
export function readRetryAfter(headers: Headers, now: number = Date.now()): number | null {
  const raw = headers.get('retry-after');

  if (raw === null) {
    return null;
  }

  const trimmed = raw.trim();

  if (trimmed === '') {
    return null;
  }

  const seconds = Number(trimmed);

  if (Number.isFinite(seconds) && seconds >= 0) {
    return seconds;
  }

  const timestamp = Date.parse(trimmed);

  if (Number.isNaN(timestamp)) {
    return null;
  }

  return Math.max(0, (timestamp - now) / 1000);
}

/** Normalizes the envelope's `errors` into a list. */
export function normalizeApiErrors(errors: unknown): ApiErrorDetail[] {
  if (errors === null || errors === undefined) {
    return [];
  }

  if (Array.isArray(errors)) {
    return errors.filter((entry): entry is ApiErrorDetail => typeof entry === 'object' && entry !== null);
  }

  if (typeof errors === 'string') {
    return errors.trim() === '' ? [] : [{ reason: errors }];
  }

  if (typeof errors === 'object') {
    return [errors as ApiErrorDetail];
  }

  return [];
}

function buildApiErrorInit(
  status: number,
  parsed: ApiEnvelope<unknown> | string | null,
  requestId: string | null,
  extra: { retryAfterSeconds: number | null; attempts: number },
): PactmanApiErrorInit {
  const envelope = typeof parsed === 'object' && parsed !== null ? parsed : null;
  const apiErrors = normalizeApiErrors(envelope?.errors);
  const reasons = apiErrors
    .map(detail => detail.reason)
    .filter((reason): reason is string => typeof reason === 'string' && reason.trim() !== '');

  const apiMessage =
    reasons.length > 0
      ? reasons.join('; ')
      : typeof envelope?.message === 'string'
        ? envelope.message
        : typeof parsed === 'string' && parsed.trim() !== ''
          ? parsed.trim().slice(0, 500)
          : null;

  return {
    status,
    apiMessage,
    apiCode: typeof envelope?.code === 'number' ? envelope.code : null,
    apiErrors,
    requestId,
    retryAfterSeconds: extra.retryAfterSeconds,
    raw: parsed,
    attempts: extra.attempts,
  };
}

async function parseBody<TData>(response: Response): Promise<ApiEnvelope<TData> | string | null> {
  const text = await response.text().catch(() => '');

  if (text.trim() === '') {
    return null;
  }

  try {
    return JSON.parse(text) as ApiEnvelope<TData>;
  } catch {
    // Preserve whatever the server sent; an unparseable body is still evidence.
    return text;
  }
}

function readRequestId(headers: Headers): string | null {
  return (
    headers.get('x-request-id') ??
    headers.get('x-correlation-id') ??
    headers.get('request-id') ??
    null
  );
}

function resolveRequestRetry(
  clientRetry: ResolvedRetryOptions,
  override: RetryOptions | false | undefined,
): ResolvedRetryOptions {
  if (override === undefined) {
    return clientRetry;
  }

  if (override === false) {
    return { ...clientRetry, maxRetries: 0 };
  }

  return {
    ...clientRetry,
    ...override,
    retryableStatuses: override.retryableStatuses
      ? [...override.retryableStatuses]
      : clientRetry.retryableStatuses,
  };
}

function throwIfAborted(signal?: AbortSignal): void {
  if (signal?.aborted) {
    throw new PactmanNetworkError('The request was aborted by the caller.', 0, {
      cause: signal.reason,
    });
  }
}

function defaultSleep(ms: number, signal?: AbortSignal): Promise<void> {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => {
      signal?.removeEventListener('abort', onAbort);
      resolve();
    }, ms);

    function onAbort() {
      clearTimeout(timer);
      reject(
        new PactmanNetworkError('The request was aborted by the caller.', 0, {
          cause: signal?.reason,
        }),
      );
    }

    signal?.addEventListener('abort', onAbort, { once: true });
  });
}

function describe(cause: unknown): string {
  if (cause instanceof Error) {
    return cause.message;
  }

  return String(cause);
}
