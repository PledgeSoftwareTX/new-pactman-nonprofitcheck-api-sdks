/**
 * Error taxonomy.
 *
 * Every error thrown by this SDK is a {@link PactmanError} carrying a stable
 * {@link PactmanErrorCategory} and an {@link PactmanErrorOrigin}, so callers can
 * branch on error type or category without parsing message strings.
 *
 * API keys are never placed into an error message, an error property, or any
 * `toJSON` output.
 */

import type { ApiErrorDetail, ApiEnvelope } from './types.js';

/** Stable, machine-comparable error categories. */
export const PactmanErrorCategory = {
  /** The client was constructed with unusable options. */
  Configuration: 'configuration',
  /** Input failed the SDK's local validation; no request was sent. */
  Validation: 'validation',
  /** HTTP 401. The API key is missing, malformed, revoked or unrecognized. */
  Authentication: 'authentication',
  /** HTTP 403. The key is valid but lacks access to the resource. */
  Authorization: 'authorization',
  /** HTTP 400. The API rejected the request. */
  BadRequest: 'bad_request',
  /** HTTP 404. No matching record. */
  NotFound: 'not_found',
  /** HTTP 429. Rate limit exceeded. */
  RateLimit: 'rate_limit',
  /** HTTP 5xx. */
  Server: 'server',
  /** The request exceeded the configured timeout. */
  Timeout: 'timeout',
  /** The request never produced an HTTP response, or the caller aborted it. */
  Network: 'network',
  /** An API error that does not fall into a more specific category. */
  Api: 'api',
} as const;

export type PactmanErrorCategory =
  (typeof PactmanErrorCategory)[keyof typeof PactmanErrorCategory];

/** Whether an error was raised locally or derived from an API response. */
export const PactmanErrorOrigin = {
  Local: 'local',
  Api: 'api',
} as const;

export type PactmanErrorOrigin = (typeof PactmanErrorOrigin)[keyof typeof PactmanErrorOrigin];

/** Base class for every error this SDK throws. */
export class PactmanError extends Error {
  readonly category: PactmanErrorCategory;
  readonly origin: PactmanErrorOrigin;

  constructor(
    message: string,
    category: PactmanErrorCategory,
    origin: PactmanErrorOrigin,
    options?: { cause?: unknown },
  ) {
    super(message);
    this.name = new.target.name;
    this.category = category;
    this.origin = origin;

    if (options?.cause !== undefined) {
      (this as { cause?: unknown }).cause = options.cause;
    }

    Object.setPrototypeOf(this, new.target.prototype);
  }

  toJSON(): Record<string, unknown> {
    return {
      name: this.name,
      message: this.message,
      category: this.category,
      origin: this.origin,
    };
  }
}

/** The client options were unusable — a missing API key, a malformed base URL. */
export class PactmanConfigurationError extends PactmanError {
  constructor(message: string) {
    super(message, PactmanErrorCategory.Configuration, PactmanErrorOrigin.Local);
  }
}

/** One item that failed local validation. */
export interface ValidationIssue {
  /** Human-readable reason the value was rejected. */
  message: string;
  /** Position in the input collection, for bulk calls. */
  index?: number;
  /** The offending value, as supplied by the caller. */
  value?: unknown;
}

/**
 * Input failed local validation. No HTTP request was sent.
 *
 * Distinguishable from an API-side 400 by `origin === 'local'`.
 */
export class PactmanValidationError extends PactmanError {
  readonly issues: ValidationIssue[];

  constructor(message: string, issues: ValidationIssue[] = []) {
    super(message, PactmanErrorCategory.Validation, PactmanErrorOrigin.Local);
    this.issues = issues;
  }

  override toJSON(): Record<string, unknown> {
    return { ...super.toJSON(), issues: this.issues };
  }
}

/** Fields shared by every error derived from an HTTP response. */
export interface PactmanApiErrorInit {
  /** HTTP status code. */
  status: number;
  /** `message` from the Pactman response envelope, when present. */
  apiMessage?: string | null;
  /** `code` from the Pactman response envelope, when present. */
  apiCode?: number | null;
  /** `errors` from the Pactman response envelope, normalized to a list. */
  apiErrors?: ApiErrorDetail[];
  /** Correlation identifier from the response headers, when present. */
  requestId?: string | null;
  /** `Retry-After` in seconds, when the server supplied a valid value. */
  retryAfterSeconds?: number | null;
  /** The parsed response body, or the raw text when it was not JSON. */
  raw?: ApiEnvelope<unknown> | string | null;
  /** How many attempts were made before this error was surfaced. */
  attempts?: number;
}

/**
 * An error returned by the Pactman API.
 *
 * Thrown directly when the status maps to no more specific subclass; response
 * metadata is preserved even when the body could not be deserialized.
 */
export class PactmanApiError extends PactmanError {
  readonly status: number;
  readonly apiMessage: string | null;
  readonly apiCode: number | null;
  readonly apiErrors: ApiErrorDetail[];
  readonly requestId: string | null;
  readonly retryAfterSeconds: number | null;
  readonly raw: ApiEnvelope<unknown> | string | null;
  readonly attempts: number;

  constructor(
    message: string,
    init: PactmanApiErrorInit,
    category: PactmanErrorCategory = PactmanErrorCategory.Api,
  ) {
    super(message, category, PactmanErrorOrigin.Api);
    this.status = init.status;
    this.apiMessage = init.apiMessage ?? null;
    this.apiCode = init.apiCode ?? null;
    this.apiErrors = init.apiErrors ?? [];
    this.requestId = init.requestId ?? null;
    this.retryAfterSeconds = init.retryAfterSeconds ?? null;
    this.raw = init.raw ?? null;
    this.attempts = init.attempts ?? 1;
  }

  override toJSON(): Record<string, unknown> {
    return {
      ...super.toJSON(),
      status: this.status,
      apiMessage: this.apiMessage,
      apiCode: this.apiCode,
      apiErrors: this.apiErrors,
      requestId: this.requestId,
      retryAfterSeconds: this.retryAfterSeconds,
      attempts: this.attempts,
    };
  }
}

/** HTTP 401. */
export class PactmanAuthenticationError extends PactmanApiError {
  constructor(message: string, init: PactmanApiErrorInit) {
    super(message, init, PactmanErrorCategory.Authentication);
  }
}

/** HTTP 403. */
export class PactmanAuthorizationError extends PactmanApiError {
  constructor(message: string, init: PactmanApiErrorInit) {
    super(message, init, PactmanErrorCategory.Authorization);
  }
}

/** HTTP 400. The API rejected the request; see `apiErrors` for the reasons. */
export class PactmanBadRequestError extends PactmanApiError {
  constructor(message: string, init: PactmanApiErrorInit) {
    super(message, init, PactmanErrorCategory.BadRequest);
  }
}

/** HTTP 404. */
export class PactmanNotFoundError extends PactmanApiError {
  constructor(message: string, init: PactmanApiErrorInit) {
    super(message, init, PactmanErrorCategory.NotFound);
  }
}

/** HTTP 429. `retryAfterSeconds` carries the server's `Retry-After` when sent. */
export class PactmanRateLimitError extends PactmanApiError {
  constructor(message: string, init: PactmanApiErrorInit) {
    super(message, init, PactmanErrorCategory.RateLimit);
  }
}

/** HTTP 5xx. */
export class PactmanServerError extends PactmanApiError {
  constructor(message: string, init: PactmanApiErrorInit) {
    super(message, init, PactmanErrorCategory.Server);
  }
}

/** The request exceeded the configured timeout. */
export class PactmanTimeoutError extends PactmanError {
  readonly timeoutMs: number;
  readonly attempts: number;

  constructor(message: string, timeoutMs: number, attempts = 1, options?: { cause?: unknown }) {
    super(message, PactmanErrorCategory.Timeout, PactmanErrorOrigin.Local, options);
    this.timeoutMs = timeoutMs;
    this.attempts = attempts;
  }

  override toJSON(): Record<string, unknown> {
    return { ...super.toJSON(), timeoutMs: this.timeoutMs, attempts: this.attempts };
  }
}

/** The request produced no HTTP response, or the caller aborted it. */
export class PactmanNetworkError extends PactmanError {
  readonly attempts: number;

  constructor(message: string, attempts = 1, options?: { cause?: unknown }) {
    super(message, PactmanErrorCategory.Network, PactmanErrorOrigin.Local, options);
    this.attempts = attempts;
  }

  override toJSON(): Record<string, unknown> {
    return { ...super.toJSON(), attempts: this.attempts };
  }
}

/** True when `value` is any error thrown by this SDK. */
export function isPactmanError(value: unknown): value is PactmanError {
  return value instanceof PactmanError;
}

/** Builds the error subclass that matches an HTTP status code. */
export function errorFromStatus(init: PactmanApiErrorInit): PactmanApiError {
  const { status } = init;
  const message = init.apiMessage?.trim() || defaultMessageForStatus(status);

  switch (status) {
    case 400:
      return new PactmanBadRequestError(message, init);
    case 401:
      return new PactmanAuthenticationError(message, init);
    case 403:
      return new PactmanAuthorizationError(message, init);
    case 404:
      return new PactmanNotFoundError(message, init);
    case 429:
      return new PactmanRateLimitError(message, init);
    default:
      if (status >= 500) {
        return new PactmanServerError(message, init);
      }

      return new PactmanApiError(message, init);
  }
}

function defaultMessageForStatus(status: number): string {
  switch (status) {
    case 400:
      return 'The Pactman API rejected the request.';
    case 401:
      return 'The Pactman API key was rejected.';
    case 403:
      return 'This Pactman API key is not permitted to access that resource.';
    case 404:
      return 'No matching record was found.';
    case 429:
      return 'The Pactman API rate limit was exceeded.';
    default:
      return status >= 500
        ? `The Pactman API returned a server error (HTTP ${status}).`
        : `The Pactman API returned an unexpected response (HTTP ${status}).`;
  }
}
