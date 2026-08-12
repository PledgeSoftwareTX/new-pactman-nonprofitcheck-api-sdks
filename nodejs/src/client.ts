/**
 * The Pactman Nonprofit Check Plus client.
 *
 * Server-side use only. The API key is a private credential; do not construct
 * this client in a browser or any other context where the bundle is shipped to
 * a user.
 */

import { normalizeEin, normalizeEins } from './ein.js';
import {
  BULK_CHECK_PATH,
  MAX_BULK_EINS,
  SINGLE_CHECK_PATH,
  type PactmanEnvironment,
} from './environments.js';
import { PactmanValidationError } from './errors.js';
import { resolveConfig, type PactmanClientOptions, type ResolvedConfig } from './config.js';
import {
  Transport,
  normalizeApiErrors,
  type RequestOptions,
  type TransportHooks,
  type TransportResponse,
} from './http.js';
import type {
  ApiEnvelope,
  ApiErrorDetail,
  BulkCheckResult,
  Nonprofit,
  SingleCheckResult,
} from './types.js';

/** Per-request options for {@link NonprofitsResource.checkBulk}. */
export interface BulkCheckOptions extends RequestOptions {
  /**
   * Remove duplicate EINs before sending, keeping first-seen order.
   *
   * Off by default: duplicates are sent exactly as supplied, because each one
   * consumes quota and silently dropping them would misreport what was checked.
   */
  dedupe?: boolean;
}

/** Nonprofit lookups. Reached through {@link PactmanClient.nonprofits}. */
export class NonprofitsResource {
  readonly #transport: Transport;

  constructor(transport: Transport) {
    this.#transport = transport;
  }

  /**
   * Checks a single nonprofit by EIN.
   *
   * The EIN is normalized and validated locally first; a malformed EIN throws
   * {@link PactmanValidationError} without sending a request.
   *
   * @example
   * ```ts
   * const result = await client.nonprofits.check('41-1787097');
   * console.log(result.nonprofit?.organization_name, result.checkCount);
   * ```
   */
  async check(ein: string, options?: RequestOptions): Promise<SingleCheckResult> {
    const normalized = normalizeEin(ein);
    const path = SINGLE_CHECK_PATH.replace('{ein}', encodeURIComponent(normalized));

    const response = await this.#transport.send<Nonprofit | null>({
      method: 'GET',
      path,
      options,
    });

    return {
      ...baseResult(response),
      nonprofit: extractNonprofit(response.body.data),
      raw: response.body,
    };
  }

  /**
   * Checks up to {@link MAX_BULK_EINS} nonprofits in one request.
   *
   * Every EIN is normalized and validated before anything is sent; if any one
   * fails, the whole call throws {@link PactmanValidationError} identifying the
   * offending index, and no request is made. EINs are sent in the order supplied
   * and duplicates are kept unless `dedupe` is set — but the API matches by set
   * membership, so the response is not ordered to match and a repeated EIN comes
   * back once. Index `organizations` by `ein` rather than pairing positionally.
   *
   * EINs the API has no record for are not an error: they arrive as HTTP 200
   * with the missing values in `notFoundEins`.
   *
   * @example
   * ```ts
   * const result = await client.nonprofits.checkBulk(['41-1787097', '996589560']);
   * for (const org of result.organizations) console.log(org.ein);
   * console.log('no record for:', result.notFoundEins);
   * ```
   */
  async checkBulk(eins: readonly string[], options?: BulkCheckOptions): Promise<BulkCheckResult> {
    if (!Array.isArray(eins)) {
      throw new PactmanValidationError(
        `checkBulk expects an array of EIN strings, received ${describeType(eins)}.`,
      );
    }

    // Materialize once so validation and serialization see identical input.
    const supplied = [...eins];

    if (supplied.length === 0) {
      throw new PactmanValidationError('checkBulk requires at least one EIN.');
    }

    const normalized = normalizeEins(supplied);
    const payload = options?.dedupe ? [...new Set(normalized)] : normalized;

    if (payload.length > MAX_BULK_EINS) {
      throw new PactmanValidationError(
        `checkBulk accepts at most ${MAX_BULK_EINS} EINs per request, received ${payload.length}. ` +
          'Split the input into batches; this SDK does not chunk automatically.',
      );
    }

    const response = await this.#transport.send<Nonprofit[] | null>({
      method: 'POST',
      path: BULK_CHECK_PATH,
      body: payload,
      options,
    });

    const base = baseResult(response);

    return {
      ...base,
      organizations: extractOrganizations(response.body.data),
      notFoundEins: extractNotFoundEins(base.errors),
      raw: response.body,
    };
  }
}

/**
 * Entry point for the SDK.
 *
 * @example
 * ```ts
 * const client = new PactmanClient({ apiKey: process.env.PACTMAN_API_KEY! });
 * ```
 */
export class PactmanClient {
  /** Nonprofit lookups. */
  readonly nonprofits: NonprofitsResource;

  readonly #config: ResolvedConfig;

  /**
   * @param options - Client configuration. `apiKey` is required.
   * @param hooks - Internal seam for injecting a clock in tests. Not covered by
   * semantic versioning; do not depend on it.
   */
  constructor(options: PactmanClientOptions, hooks?: TransportHooks) {
    const { apiKey, config } = resolveConfig(options);
    this.#config = config;
    this.nonprofits = new NonprofitsResource(new Transport(apiKey, config, hooks));
  }

  /** The resolved base URL every request is sent to. */
  get baseUrl(): string {
    return this.#config.baseUrl;
  }

  /** The named environment in use, or `null` when an explicit `baseUrl` was given. */
  get environment(): PactmanEnvironment | null {
    return this.#config.environment;
  }

  /** The resolved timeout in milliseconds. */
  get timeoutMs(): number {
    return this.#config.timeoutMs;
  }

  /**
   * A redacted view of the configuration.
   *
   * The API key is not a property of this object and never appears here, in
   * `JSON.stringify`, or in `console.log`.
   */
  toJSON(): Record<string, unknown> {
    return {
      baseUrl: this.#config.baseUrl,
      environment: this.#config.environment,
      timeoutMs: this.#config.timeoutMs,
      retry: this.#config.retry,
      maxRequestsPerSecond: this.#config.maxRequestsPerSecond,
      userAgent: this.#config.userAgent,
      apiKey: '[redacted]',
    };
  }

  /** Keeps `console.log(client)` and `util.inspect` free of the API key. */
  [Symbol.for('nodejs.util.inspect.custom')](): Record<string, unknown> {
    return { ...this.toJSON(), name: 'PactmanClient' };
  }

  toString(): string {
    return `PactmanClient(${this.#config.baseUrl})`;
  }
}

function baseResult<TData>(
  response: TransportResponse<TData>,
): Omit<SingleCheckResult, 'nonprofit' | 'raw'> {
  const envelope = response.body ?? {};

  return {
    checkCount: typeof envelope.nonprofit_check_count === 'number' ? envelope.nonprofit_check_count : null,
    timeTakenMs: typeof envelope.timeTaken === 'number' ? envelope.timeTaken : null,
    errors: normalizeApiErrors(envelope.errors),
    requestId: response.requestId,
    status: response.status,
  };
}

function extractNonprofit(data: unknown): Nonprofit | null {
  if (data === null || data === undefined) {
    return null;
  }

  if (Array.isArray(data)) {
    return (data[0] as Nonprofit | undefined) ?? null;
  }

  return typeof data === 'object' ? (data as Nonprofit) : null;
}

/**
 * The published schema returns `data` as an array. Some deployments wrap it as
 * `{ organizations: [...] }`, so both are accepted rather than silently
 * yielding an empty list.
 */
function extractOrganizations(data: unknown): Nonprofit[] {
  if (Array.isArray(data)) {
    return data as Nonprofit[];
  }

  if (data !== null && typeof data === 'object') {
    const wrapped = (data as { organizations?: unknown }).organizations;

    if (Array.isArray(wrapped)) {
      return wrapped as Nonprofit[];
    }
  }

  return [];
}

function extractNotFoundEins(errors: ApiErrorDetail[]): string[] {
  const found: string[] = [];

  for (const detail of errors) {
    const { eins } = detail;

    if (Array.isArray(eins)) {
      found.push(...eins.filter((ein): ein is string => typeof ein === 'string'));
    } else if (typeof eins === 'string') {
      found.push(...eins.split(',').map(ein => ein.trim()).filter(ein => ein !== ''));
    }
  }

  return found;
}

function describeType(value: unknown): string {
  if (value === null) {
    return 'null';
  }

  return Array.isArray(value) ? 'array' : typeof value;
}

/** Re-exported so `ApiEnvelope` is reachable from this module's consumers. */
export type { ApiEnvelope };
