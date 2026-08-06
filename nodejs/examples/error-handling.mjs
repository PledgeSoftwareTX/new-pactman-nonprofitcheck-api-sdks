/**
 * Branching on error type: local validation, authentication, and rate limits.
 *
 * Run:  PACTMAN_API_KEY=... node examples/error-handling.mjs
 */
import {
  PactmanApiError,
  PactmanAuthenticationError,
  PactmanClient,
  PactmanNetworkError,
  PactmanRateLimitError,
  PactmanTimeoutError,
  PactmanValidationError,
} from '@pactmandev/nonprofit-check-plus';

const apiKey = process.env.PACTMAN_API_KEY;

if (!apiKey) {
  console.error('Set PACTMAN_API_KEY before running this example.');
  process.exit(1);
}

const client = new PactmanClient({
  apiKey,
  ...(process.env.PACTMAN_BASE_URL ? { baseUrl: process.env.PACTMAN_BASE_URL } : {}),
  timeoutMs: 10_000,
  retry: { maxRetries: 2 },
});

/** One place to turn any SDK failure into an action. No string parsing. */
function explain(error) {
  if (error instanceof PactmanValidationError) {
    const detail = error.issues.length > 0 ? error.issues.map(i => i.message).join(' ') : error.message;

    return `Local validation — fix the input. ${detail}`;
  }

  if (error instanceof PactmanAuthenticationError) {
    return 'Authentication — the API key was rejected. Check PACTMAN_API_KEY.';
  }

  if (error instanceof PactmanRateLimitError) {
    return `Rate limited — retry after ${error.retryAfterSeconds ?? 'an unspecified'} seconds.`;
  }

  if (error instanceof PactmanTimeoutError) {
    return `Timed out after ${error.timeoutMs}ms — raise timeoutMs or retry later.`;
  }

  if (error instanceof PactmanNetworkError) {
    return 'Network failure — the request never reached the API.';
  }

  if (error instanceof PactmanApiError) {
    return `API error ${error.status} (request ${error.requestId ?? 'unknown'}): ${error.message}`;
  }

  return `Unexpected: ${String(error)}`;
}

// 1. A malformed EIN never leaves the process.
try {
  await client.nonprofits.check('41178709');
} catch (error) {
  console.log('malformed EIN ->', explain(error));
}

// 2. An empty batch is rejected locally too.
try {
  await client.nonprofits.checkBulk([]);
} catch (error) {
  console.log('empty batch   ->', explain(error));
}

// 3. A bad key produces an authentication error on first use.
try {
  const badClient = new PactmanClient({
    apiKey: 'obviously-not-a-real-key',
    ...(process.env.PACTMAN_BASE_URL ? { baseUrl: process.env.PACTMAN_BASE_URL } : {}),
    retry: false,
  });

  await badClient.nonprofits.check('411787097');
  console.log('bad key       -> unexpectedly succeeded');
} catch (error) {
  console.log('bad key       ->', explain(error));
}

// 4. A real call, handled the same way.
try {
  const result = await client.nonprofits.check('41-1787097');
  console.log('valid check   ->', result.nonprofit?.organization_name ?? 'no record');
} catch (error) {
  console.log('valid check   ->', explain(error));
}
