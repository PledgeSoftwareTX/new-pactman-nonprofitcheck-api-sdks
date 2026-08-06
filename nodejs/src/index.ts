/**
 * Pactman Nonprofit Check Plus SDK for Node.js.
 *
 * Server-side only — the API key is a private credential.
 *
 * @example
 * ```ts
 * import { PactmanClient } from '@pactmandev/nonprofit-check-plus';
 *
 * const client = new PactmanClient({ apiKey: process.env.PACTMAN_API_KEY! });
 * const { nonprofit } = await client.nonprofits.check('41-1787097');
 * ```
 *
 * @packageDocumentation
 */

export { PactmanClient, NonprofitsResource, type BulkCheckOptions } from './client.js';

export {
  DEFAULT_TIMEOUT_MS,
  type FetchLike,
  type PactmanClientOptions,
  type ResolvedConfig,
  type ResolvedRetryOptions,
  type RetryOptions,
} from './config.js';

export {
  BULK_CHECK_PATH,
  DEFAULT_ENVIRONMENT,
  MAX_BULK_EINS,
  PactmanEnvironment,
  SINGLE_CHECK_PATH,
  baseUrlForEnvironment,
  supportedEnvironments,
} from './environments.js';

export { EIN_LENGTH, isValidEin, normalizeEin, normalizeEins } from './ein.js';

export {
  PactmanApiError,
  PactmanAuthenticationError,
  PactmanAuthorizationError,
  PactmanBadRequestError,
  PactmanConfigurationError,
  PactmanError,
  PactmanErrorCategory,
  PactmanErrorOrigin,
  PactmanNetworkError,
  PactmanNotFoundError,
  PactmanRateLimitError,
  PactmanServerError,
  PactmanTimeoutError,
  PactmanValidationError,
  isPactmanError,
  type PactmanApiErrorInit,
  type ValidationIssue,
} from './errors.js';

export { type RequestOptions } from './http.js';

export {
  getAroe,
  getBmf,
  getOfac,
  getPub78,
  type AroeSource,
  type BmfSource,
  type OfacSource,
  type Pub78Source,
} from './sources.js';

export type {
  ApiEnvelope,
  ApiErrorDetail,
  BulkCheckResult,
  Nonprofit,
  OrganizationType,
  PactmanResult,
  SingleCheckResult,
} from './types.js';

export { VERSION } from './version.js';
