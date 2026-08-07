/**
 * Bulk nonprofit check with local validation and result iteration.
 *
 * Run:  PACTMAN_API_KEY=... node examples/bulk.mjs
 */
import {
  MAX_BULK_EINS,
  PactmanClient,
  PactmanValidationError,
  getPub78,
} from '@pactmandev/nonprofit-check-plus';

const apiKey = process.env.PACTMAN_API_KEY;

if (!apiKey) {
  console.error('Set PACTMAN_API_KEY before running this example.');
  process.exit(1);
}

const client = new PactmanClient({
  apiKey,
  ...(process.env.PACTMAN_BASE_URL ? { baseUrl: process.env.PACTMAN_BASE_URL } : {}),
});

const eins = ['41-1787097', '996589560'];

console.log(`Checking ${eins.length} EINs (server limit is ${MAX_BULK_EINS} per request).`);

try {
  const result = await client.nonprofits.checkBulk(eins);

  console.log(`\nMatched ${result.organizations.length} organizations.`);

  for (const org of result.organizations) {
    const pub78 = getPub78(org);
    console.log(`  ${org.ein}  ${org.organization_name}  pub78_listed=${pub78?.verified ?? 'n/a'}`);
  }

  // EINs with no record come back on a successful response, not as an error.
  if (result.notFoundEins.length > 0) {
    console.log(`\nNo record for: ${result.notFoundEins.join(', ')}`);
  }

  console.log(`\nChecks consumed: ${result.checkCount}`);
} catch (error) {
  if (error instanceof PactmanValidationError) {
    // Nothing was sent — the whole batch is rejected before the request.
    console.error('Local validation failed, no request was sent:');

    for (const issue of error.issues) {
      console.error(`  index ${issue.index}: ${issue.message}`);
    }

    process.exit(1);
  }

  throw error;
}

// Duplicates are sent as supplied, because each one consumes quota. Pass
// { dedupe: true } to collapse them first.
