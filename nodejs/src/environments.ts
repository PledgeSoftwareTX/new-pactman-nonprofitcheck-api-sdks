/**
 * Environment selection and base-URL resolution.
 *
 * Endpoint hosts are declared here and nowhere else. Nothing in this package
 * should contain a literal Pactman host.
 */

/** Named Pactman environments that are supported for public SDK use. */
export const PactmanEnvironment = {
  /** The Pactman production API. */
  Production: 'production',
} as const;

export type PactmanEnvironment = (typeof PactmanEnvironment)[keyof typeof PactmanEnvironment];

/**
 * Base URL for each named environment.
 *
 * Pactman's QA, SIT and sandbox hosts are internal and are deliberately not
 * exposed here. Point at one with the `baseUrl` option if you have been given
 * access to it.
 */
const BASE_URLS: Record<PactmanEnvironment, string> = {
  [PactmanEnvironment.Production]: 'https://entities.pactman.org',
};

/** The environment used when none is supplied. */
export const DEFAULT_ENVIRONMENT: PactmanEnvironment = PactmanEnvironment.Production;

/** Path of the single-check endpoint. `{ein}` is replaced with a normalized EIN. */
export const SINGLE_CHECK_PATH = '/api/entities/nonprofitcheck/v1/us/ein/{ein}';

/** Path of the bulk-check endpoint. */
export const BULK_CHECK_PATH = '/api/entities/nonprofitcheckbulk/v1/us/eins';

/**
 * Maximum number of EINs the API accepts in one bulk request.
 *
 * This mirrors the server-side limit. It is declared once, here.
 */
export const MAX_BULK_EINS = 50;

/** Returns the base URL for a named environment. */
export function baseUrlForEnvironment(environment: PactmanEnvironment): string {
  const baseUrl = BASE_URLS[environment];

  if (!baseUrl) {
    const supported = Object.values(PactmanEnvironment).join(', ');
    throw new Error(`Unknown Pactman environment "${environment}". Supported: ${supported}.`);
  }

  return baseUrl;
}

/** Every environment name the SDK understands. */
export function supportedEnvironments(): PactmanEnvironment[] {
  return Object.values(PactmanEnvironment);
}
