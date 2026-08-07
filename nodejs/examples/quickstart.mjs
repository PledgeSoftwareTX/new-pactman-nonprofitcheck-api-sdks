/**
 * Minimal single nonprofit check.
 *
 * Run:  PACTMAN_API_KEY=... node examples/quickstart.mjs [EIN]
 *
 * The key is read from the environment. Never hard-code it, and never run this
 * in a browser — the key is a private server-side credential.
 */
import { PactmanClient, getBmf, getOfac, getPub78 } from '@pactmandev/nonprofit-check-plus';

const apiKey = process.env.PACTMAN_API_KEY;

if (!apiKey) {
  console.error('Set PACTMAN_API_KEY before running this example.');
  process.exit(1);
}

const client = new PactmanClient({
  apiKey,
  // Production is the default. PACTMAN_BASE_URL is only for a local mock server.
  ...(process.env.PACTMAN_BASE_URL ? { baseUrl: process.env.PACTMAN_BASE_URL } : {}),
  timeoutMs: 15_000,
});

const ein = process.argv[2] ?? '41-1787097';
const result = await client.nonprofits.check(ein);

if (!result.nonprofit) {
  console.log(`No record for EIN ${ein}.`);
  process.exit(0);
}

const { nonprofit } = result;

console.log(`Organization : ${nonprofit.organization_name}`);
console.log(`EIN          : ${nonprofit.ein}`);
console.log(`Location     : ${nonprofit.city}, ${nonprofit.state}`);
console.log(`Profile      : ${nonprofit.pactman_org_url}`);
console.log(`Checks used  : ${result.checkCount}`);

// Two source-specific findings, read straight from the API response.
const pub78 = getPub78(nonprofit);
const bmf = getBmf(nonprofit);
const ofac = getOfac(nonprofit);

console.log('\nIRS Publication 78');
console.log(
  pub78 === null ? '  not returned' : `  listed: ${pub78.verified}, as of ${pub78.most_recent}`,
);

console.log('\nIRS Business Master File');
console.log(
  bmf === null
    ? '  not returned'
    : `  status: ${bmf.status}, subsection: ${bmf.subsection_description}`,
);

console.log('\nOFAC');
console.log(ofac === null ? '  not returned' : `  ${ofac.status}`);

// A syntactically valid EIN and a clean set of findings are not an eligibility
// decision. Apply your own grantmaking, compliance and risk policy.
