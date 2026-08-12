/**
 * EX-16 — EIN not found, and application-level failures.
 *
 * A well-formed EIN with no matching record is a normal outcome, not a bug. The
 * single endpoint answers HTTP 404, which the SDK raises as
 * `PactmanNotFoundError` — a subclass of `PactmanApiError`, so a handler can
 * catch the specific case or the general one.
 *
 * The envelope's own `code`, `message` and `errors` survive onto the error, and
 * none of the diagnostics contain the API key.
 *
 * Run:  PACTMAN_API_KEY=... node examples/ex-16-not-found.mjs
 */
import {
  PactmanApiError,
  PactmanErrorCategory,
  PactmanNotFoundError,
  isPactmanError,
} from '@pactmandev/nonprofit-check-plus';
import { FIXTURE_EINS, withFixtureApi } from './lib/fixture-api.mjs';
import { bullet, field, heading, note } from './lib/print.mjs';

await withFixtureApi(async client => {
  heading(`Single check for ${FIXTURE_EINS.noRecord} — well formed, no record`);

  try {
    const result = await client.nonprofits.check(FIXTURE_EINS.noRecord);
    console.log(`  Unexpectedly succeeded: ${result.nonprofit?.organization_name}`);
  } catch (error) {
    if (!(error instanceof PactmanNotFoundError)) {
      throw error;
    }

    // Stable identity: class, category, and origin. Never parse `message`.
    field('class', error.constructor.name);
    field('category', error.category);
    field('origin', error.origin);
    field('is a PactmanApiError', error instanceof PactmanApiError);
    field('isPactmanError', isPactmanError(error));
    field('matches NotFound category', error.category === PactmanErrorCategory.NotFound);

    heading('  Response detail carried on the error');
    field('status', error.status);
    field('apiCode (envelope code)', error.apiCode);
    field('apiMessage', error.apiMessage);
    field('requestId', error.requestId);
    field('attempts', error.attempts);
    field('retryAfterSeconds', error.retryAfterSeconds);

    for (const detail of error.apiErrors) {
      bullet(`resource=${detail.resource} code=${detail.code ?? '-'} reason=${detail.reason}`);
    }

    // Sanitized diagnostics: safe to log, safe to attach to a support ticket.
    heading('  error.toJSON() — what you can safely log');
    console.log(
      JSON.stringify(error, null, 2)
        .split('\n')
        .map(line => `    ${line}`)
        .join('\n'),
    );

    const serialized = JSON.stringify(error) + String(error.stack);
    field('contains the API key', serialized.includes(process.env.PACTMAN_API_KEY));

    // 404 is never retried, whatever the retry policy says.
    field('attempts made', `${error.attempts} — not-found is not a transient failure`);
  }

  // The bulk endpoint behaves differently, and this is the part that surprises
  // people: unmatched EINs come back on a successful 200 as item-level errors.
  // Only a request where *nothing* matched is a 404.
  heading('Bulk — mixed input returns HTTP 200, not an error');

  const mixed = await client.nonprofits.checkBulk([
    FIXTURE_EINS.publicCharity,
    FIXTURE_EINS.noRecord,
  ]);

  field('status', mixed.status);
  field('organizations returned', mixed.organizations.length);
  field('notFoundEins', mixed.notFoundEins.join(', '));

  heading('Bulk — nothing matched at all');

  try {
    await client.nonprofits.checkBulk([FIXTURE_EINS.noRecord]);
    console.log('  Unexpectedly succeeded.');
  } catch (error) {
    if (!(error instanceof PactmanApiError)) {
      throw error;
    }

    field('class', error.constructor.name);
    field('status', error.status);
    field('apiMessage', error.apiMessage);
  }
});

note(
  'Distinguish "we could not find it" from "we could not ask". A 404 means the\n' +
    'record is absent; a timeout or a 503 means you learned nothing. Only the first\n' +
    'is a fact about the organization.',
);
