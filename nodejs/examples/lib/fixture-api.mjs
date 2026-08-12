/**
 * Access to the bundled fixture API.
 *
 * Some scenarios cannot be summoned on demand from the production API: a revoked
 * exemption, an OFAC match, a cross-source conflict, an HTTP 429, a response
 * carrying a field newer than this SDK. Examples that need one of those run
 * against the fixture server in `scripts/mock-server.mjs`, which speaks the same
 * envelope, error and check-count semantics as the real service.
 *
 * Set `PACTMAN_BASE_URL` to point these examples somewhere else instead.
 */
import { PactmanClient } from '@pactmandev/nonprofit-check-plus';
import { startMockServer } from '../../scripts/mock-server.mjs';
import { requireApiKey } from './client.mjs';

export { CONTROL_EINS, FIXTURE_EINS, KNOWN_NONPROFIT_FIELDS } from '../../scripts/fixtures.mjs';

/**
 * Runs `body` with a client pointed at the fixture API.
 *
 * The server is started only when `PACTMAN_BASE_URL` is unset, and is always
 * closed afterwards, so the example leaves no background work behind.
 *
 * @param body      Receives `(client, baseUrl)`.
 * @param overrides Extra {@link PactmanClient} options for this example.
 */
export async function withFixtureApi(body, overrides = {}) {
  const apiKey = requireApiKey();
  const external = process.env.PACTMAN_BASE_URL;
  const fixture = external ? null : await startMockServer({ apiKey });
  const baseUrl = external ?? fixture.url;

  if (!external) {
    console.log(`Using the bundled fixture API at ${baseUrl} — these scenarios need`);
    console.log('records and responses a live API will not produce on request.');
  }

  const client = new PactmanClient({ apiKey, baseUrl, timeoutMs: 15_000, ...overrides });

  try {
    return await body(client, baseUrl);
  } finally {
    fixture?.close();
  }
}
