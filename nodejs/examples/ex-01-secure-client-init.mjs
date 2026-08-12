/**
 * EX-01 — Secure client initialization.
 *
 * Loads the API key from an environment variable, selects the environment,
 * configures a finite timeout, and builds one reusable client. Then it proves
 * the key does not leak into logs, debug output, or exceptions.
 *
 * Run:  PACTMAN_API_KEY=... node examples/ex-01-secure-client-init.mjs
 */
import { inspect } from 'node:util';
import {
  DEFAULT_TIMEOUT_MS,
  PactmanClient,
  PactmanConfigurationError,
  PactmanEnvironment,
} from '@pactmandev/nonprofit-check-plus';
import { field, heading, note } from './lib/print.mjs';

// 1. The key comes from the environment. It is never a literal in source, never
//    committed, and never shipped to a browser or mobile bundle — anyone who
//    opens devtools on a page holding this key owns your quota.
const apiKey = process.env.PACTMAN_API_KEY;

if (!apiKey) {
  console.error('Set PACTMAN_API_KEY before running this example.');
  console.error('Load it from your secret manager or a .env file excluded from git.');
  process.exit(1);
}

// 2. One client, built once, reused for the life of the process. Constructing a
//    client per request throws away connection reuse and any throttle state.
const client = new PactmanClient({
  apiKey,

  // Production is the default; naming it makes the intent explicit at review time.
  environment: PactmanEnvironment.Production,

  // 3. A finite timeout. The default is 30s and there is no way to disable it,
  //    but a caller-facing service usually wants something shorter.
  timeoutMs: 10_000,

  // A mock or a host Pactman gave you directly overrides `environment`.
  ...(process.env.PACTMAN_BASE_URL ? { baseUrl: process.env.PACTMAN_BASE_URL } : {}),
});

heading('Resolved configuration');
field('baseUrl', client.baseUrl);
field('environment', client.environment);
field('timeoutMs', client.timeoutMs);
field('SDK default timeout', DEFAULT_TIMEOUT_MS);

// 4. Every diagnostic surface is checked against the real key. None of them
//    contain it — `apiKey` is not a property of the client, and the error types
//    never copy it into a message or a serialized field.
let caughtError = null;

try {
  new PactmanClient({ apiKey, baseUrl: 'not-a-url' });
} catch (error) {
  caughtError = error;
}

const surfaces = {
  'console.log(client)': inspect(client),
  'JSON.stringify(client)': JSON.stringify(client),
  'client.toString()': client.toString(),
  'error.message': String(caughtError?.message),
  'JSON.stringify(error)': JSON.stringify(caughtError),
  'error.stack': String(caughtError?.stack),
};

heading('Credential redaction');

for (const [surface, text] of Object.entries(surfaces)) {
  field(surface, text.includes(apiKey) ? 'LEAKED THE KEY' : 'clean');
}

const leaked = Object.values(surfaces).some(text => text.includes(apiKey));

heading('Client as printed');
console.log(inspect(client, { depth: 3 }));

field('\nConfiguration error type', caughtError instanceof PactmanConfigurationError);

note(
  'The key is sent only as an Authorization header at request time. Rotate it if\n' +
    'it is ever printed, logged, or committed.',
);

if (leaked) {
  process.exit(1);
}
