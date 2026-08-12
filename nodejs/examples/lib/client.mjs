/**
 * Client bootstrap shared by the numbered examples.
 *
 * This is the pattern from `ex-01-secure-client-init.mjs`, factored out so the
 * other examples can stay on their own subject. Nothing here is part of the SDK.
 */
import { PactmanClient } from '@pactmandev/nonprofit-check-plus';

/**
 * Reads the key from the environment, or exits with an explanation.
 *
 * The key is never printed, embedded in a message, or written to a file.
 */
export function requireApiKey() {
  const apiKey = process.env.PACTMAN_API_KEY;

  if (!apiKey) {
    console.error('Set PACTMAN_API_KEY before running this example.');
    process.exit(1);
  }

  return apiKey;
}

/**
 * A reusable client, pointed at production unless `PACTMAN_BASE_URL` overrides
 * it. Build one per process and share it — each instance carries its own
 * throttle state and connection reuse.
 */
export function createClient(overrides = {}) {
  return new PactmanClient({
    apiKey: requireApiKey(),
    ...(process.env.PACTMAN_BASE_URL ? { baseUrl: process.env.PACTMAN_BASE_URL } : {}),
    timeoutMs: 15_000,
    ...overrides,
  });
}
