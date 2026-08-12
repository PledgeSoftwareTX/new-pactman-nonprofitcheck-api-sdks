/**
 * EX-20 — Bulk batch-size validation.
 *
 * The batch limit is the server's. The SDK exports it as `MAX_BULK_EINS` and
 * checks against it locally, so an over-limit batch fails in-process instead of
 * spending a round trip to be told no.
 *
 * `MAX_BULK_EINS` is declared once in the SDK. Import it — do not copy the
 * number into your own constants file, where it will outlive the server's.
 *
 * Run:  PACTMAN_API_KEY=... node examples/ex-20-bulk-batch-limits.mjs
 */
import {
  MAX_BULK_EINS,
  PactmanBadRequestError,
  PactmanValidationError,
} from '@pactmandev/nonprofit-check-plus';
import { FIXTURE_EINS, withFixtureApi } from './lib/fixture-api.mjs';
import { bullet, field, heading, note } from './lib/print.mjs';

/** Fills a batch with well-formed EINs, so only the size is under test. */
function batchOfSize(size) {
  return Array.from({ length: size }, (_, index) => String(100000000 + index));
}

await withFixtureApi(async client => {
  heading('The authoritative limit');
  field('MAX_BULK_EINS', MAX_BULK_EINS);
  bullet('Exported by the SDK, mirroring the server-side maximum.');
  bullet('Referenced here; not redeclared.');

  heading('Empty collection');

  try {
    await client.nonprofits.checkBulk([]);
    console.log('  Unexpectedly accepted.');
  } catch (error) {
    if (!(error instanceof PactmanValidationError)) {
      throw error;
    }

    field('class', error.constructor.name);
    field('origin', error.origin);
    field('message', error.message);
    field('request sent', 'no');
  }

  heading(`Over-limit collection (${MAX_BULK_EINS + 1} EINs)`);

  try {
    await client.nonprofits.checkBulk(batchOfSize(MAX_BULK_EINS + 1));
    console.log('  Unexpectedly accepted.');
  } catch (error) {
    if (!(error instanceof PactmanValidationError)) {
      throw error;
    }

    field('class', error.constructor.name);
    field('origin', error.origin);
    field('message', error.message);
    field('request sent', 'no');
  }

  heading(`At the limit (${MAX_BULK_EINS} EINs)`);

  // Accepted locally and sent. Most of these EINs have no record, so this comes
  // back as a partial success — the size was never the problem.
  const atLimit = [FIXTURE_EINS.publicCharity, ...batchOfSize(MAX_BULK_EINS - 1)];

  const result = await client.nonprofits.checkBulk(atLimit);

  field('EINs sent', atLimit.length);
  field('status', result.status);
  field('organizations returned', result.organizations.length);
  field('notFoundEins', result.notFoundEins.length);

  // If the server ever tightens its limit below the SDK's, the local check will
  // pass and the server will answer 400. That message is authoritative; surface
  // it rather than trusting the constant.
  heading('If the server disagrees with the constant');
  bullet('A server-side rejection arrives as PactmanBadRequestError.');
  bullet('`apiErrors[].reason` carries the limit the server actually enforces.');
  bullet(`Catch ${PactmanBadRequestError.name} and log the reason verbatim.`);

  // Chunking is your decision, not the SDK's: it refuses to split a batch,
  // because doing so quietly turns one billable request into several.
  heading('Splitting a larger list');

  const largeList = batchOfSize(120);
  const batches = [];

  for (let index = 0; index < largeList.length; index += MAX_BULK_EINS) {
    batches.push(largeList.slice(index, index + MAX_BULK_EINS));
  }

  field('input size', largeList.length);
  field('batches', batches.length);
  field('batch sizes', batches.map(batch => batch.length).join(', '));
  bullet('The SDK never chunks for you — each batch below is a request you chose to make.');
});

note(
  'One constant, imported everywhere. A hardcoded 50 scattered through a codebase\n' +
    'is a migration waiting to be missed.',
);
