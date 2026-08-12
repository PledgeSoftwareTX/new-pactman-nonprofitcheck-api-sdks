/**
 * EX-25 — Raw response and forward compatibility.
 *
 * The typed model and the raw envelope are both available, and the raw one is
 * not a debugging afterthought. When the API adds a field, the SDK you have
 * installed keeps working and the new field is readable immediately — no
 * upgrade, no deserialization failure, no dropped data.
 *
 * The fixture used here is an approved response from a newer API version. It
 * carries fields this SDK has never heard of and an enum value outside the
 * documented set.
 *
 * Run:  PACTMAN_API_KEY=... node examples/ex-25-raw-and-forward-compat.mjs
 */
import { getBmf, getPub78 } from '@pactmandev/nonprofit-check-plus';
import { FIXTURE_EINS, KNOWN_NONPROFIT_FIELDS, withFixtureApi } from './lib/fixture-api.mjs';
import { bullet, field, heading, note } from './lib/print.mjs';

/** Documented foundation types. Anything else is unknown, not wrong. */
const KNOWN_FOUNDATION_TYPES = new Set(['pc', 'pf', 'po']);

await withFixtureApi(async client => {
  const result = await client.nonprofits.check(FIXTURE_EINS.futureFields);
  const { nonprofit } = result;

  if (!nonprofit) {
    console.log('No record returned.');
    return;
  }

  // Known fields deserialize exactly as they always have.
  heading('Known fields are unaffected');
  field('ein', nonprofit.ein);
  field('organization_name', nonprofit.organization_name);
  field('bmf_status', getBmf(nonprofit)?.status);
  field('pub78_verified', getPub78(nonprofit)?.verified);
  field('subsection_description', getBmf(nonprofit)?.subsection_description);

  // Unknown fields ride along on the same object. No cast, no upgrade.
  const unknownFields = Object.keys(nonprofit).filter(key => !KNOWN_NONPROFIT_FIELDS.has(key));

  heading('Fields this SDK version does not declare');
  field('count', unknownFields.length);

  for (const key of unknownFields) {
    bullet(`${key} = ${JSON.stringify(nonprofit[key])}`);
  }

  // In TypeScript these are reachable through the index signature, typed as
  // `unknown`, so you narrow them deliberately:
  //
  //   const status = nonprofit['state_charity_registration_status'];
  //   if (typeof status === 'string') { /* ... */ }
  const registration = nonprofit['state_charity_registration_status'];

  field('read via index access', typeof registration === 'string' ? registration : '<not a string>');

  // An unknown value in a known field. This is the one that breaks applications
  // that map eagerly into an enum and default the miss.
  heading('An unrecognized value in a documented field');

  const foundationType = getBmf(nonprofit)?.foundation_type_code;

  field('foundation_type_code', foundationType);
  field('in the documented set', KNOWN_FOUNDATION_TYPES.has(foundationType));
  field('foundation_type_description', getBmf(nonprofit)?.foundation_type_description);
  field(
    'handled as',
    KNOWN_FOUNDATION_TYPES.has(foundationType)
      ? 'a known classification'
      : 'unknown — routed to review, not defaulted to a known type',
  );

  // Nested objects keep their unknown members too.
  const [firstType] = getPub78(nonprofit)?.organization_types ?? [];

  heading('Unknown members inside a known object');
  field('deductibility_limitation', firstType?.deductibility_limitation);
  field('deductibility_status_description', firstType?.deductibility_status_description);
  field('future_deductibility_note', firstType?.future_deductibility_note);

  // And the whole envelope, byte for byte as parsed.
  heading('The raw envelope');
  field('raw.code', result.raw.code);
  field('raw.message', result.raw.message);
  field('raw.timeTaken', result.raw.timeTaken);
  field('raw.nonprofit_check_count', result.raw.nonprofit_check_count);
  field('raw.data is the record', result.raw.data === nonprofit);
  field('top-level envelope keys', Object.keys(result.raw).join(', '));

  bullet('Persist `raw` when you need to prove later what the API actually said.');
  bullet('It is the parsed body, unmodified — nothing was dropped on the way through.');
});

note(
  'Forward compatibility cuts both ways: an unknown value must never be coerced\n' +
    'into a known one. "I do not recognize this" is a valid, and usually safer,\n' +
    'outcome than a confident wrong answer.',
);
