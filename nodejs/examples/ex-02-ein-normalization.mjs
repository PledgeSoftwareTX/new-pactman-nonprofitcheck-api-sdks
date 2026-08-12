/**
 * EX-02 — EIN normalization before a single check.
 *
 * An EIN arrives from an onboarding form with a hyphen and stray whitespace. The
 * SDK normalizes it to nine digits before building the request URL; the original
 * input is kept locally so support can see exactly what the applicant typed.
 *
 * Run:  PACTMAN_API_KEY=... node examples/ex-02-ein-normalization.mjs
 */
import { isValidEin, normalizeEin } from '@pactmandev/nonprofit-check-plus';
import { createClient } from './lib/client.mjs';
import { field, heading, note } from './lib/print.mjs';
import { FIXTURE_EINS } from './lib/fixture-api.mjs';

const client = createClient();

// What a form actually submits, versus what the endpoint expects.
const submitted = `  ${FIXTURE_EINS.publicCharity.slice(0, 2)}-${FIXTURE_EINS.publicCharity.slice(2)}  `;

heading('Normalization');
field('as submitted', JSON.stringify(submitted));
field('isValidEin', isValidEin(submitted));
field('normalized', normalizeEin(submitted));
field('hyphenless input', normalizeEin(FIXTURE_EINS.publicCharity));

// Both inputs address the same organization, so they are the same request.
field(
  'same request',
  normalizeEin(submitted) === normalizeEin(FIXTURE_EINS.publicCharity),
);

// Keep the raw input alongside the normalized value for local diagnostics. Store
// the normalized form as your key — that is what the API echoes back.
const applicant = {
  einAsSubmitted: submitted,
  ein: normalizeEin(submitted),
};

// `check` normalizes internally too, so passing the raw string is safe. Doing it
// up front means your own records and the API's agree on one canonical value.
const result = await client.nonprofits.check(applicant.einAsSubmitted);

heading('Response');
field('EIN in request', applicant.ein);
field('EIN in response', result.nonprofit?.ein);
field('organization_name', result.nonprofit?.organization_name);

note(
  'Normalization is a formatting step. A nine-digit value is not evidence that an\n' +
    'organization exists, is tax-exempt, or is in good standing.',
);
