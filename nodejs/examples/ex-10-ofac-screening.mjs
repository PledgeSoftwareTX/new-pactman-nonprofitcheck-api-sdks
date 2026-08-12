/**
 * EX-10 — OFAC screening result.
 *
 * The API reports OFAC as a sentence, not a flag. Four results have to stay
 * distinguishable, because they route to four different places:
 *
 *   no_match     the organization was screened and was not on the SDN list
 *   match        a close match was found — never auto-clear this
 *   null         the field was returned with no value
 *   unavailable  no OFAC field was returned at all; nothing was screened
 *
 * The SDK exposes no `hasOfacMatch` boolean. Deriving one means pattern-matching
 * English that the source can reword at any time, and a screening step that
 * silently starts returning "no match" because a sentence changed is worse than
 * no screening step.
 *
 * Run:  PACTMAN_API_KEY=... node examples/ex-10-ofac-screening.mjs
 */
import { getOfac } from '@pactmandev/nonprofit-check-plus';
import { FIXTURE_EINS, withFixtureApi } from './lib/fixture-api.mjs';
import { field, heading, note } from './lib/print.mjs';

/**
 * Classifies the OFAC finding into the four states above.
 *
 * The one textual test here is for the SDN unique identifier the API includes on
 * a match. It is treated as a signal to escalate, never as a signal to clear:
 * anything unrecognized falls through to `needs_review`.
 */
function classifyOfac(nonprofit) {
  const ofac = getOfac(nonprofit);

  if (ofac === null) {
    return { state: 'unavailable', status: undefined, publishedDate: undefined };
  }

  const { status, list_published_date: publishedDate } = ofac;

  if (status === null || status === undefined) {
    return { state: 'null', status, publishedDate };
  }

  if (/UID:/i.test(status)) {
    return { state: 'match', status, publishedDate };
  }

  if (/NOT included/i.test(status)) {
    return { state: 'no_match', status, publishedDate };
  }

  return { state: 'needs_review', status, publishedDate };
}

/** Four states, four destinations. None of them is "approve automatically". */
const ROUTING = {
  no_match: 'continue — screened against the SDN list with no match',
  match: 'block and escalate to compliance — a possible SDN match must be adjudicated',
  null: 'hold — the field was returned empty; treat as unscreened, not as cleared',
  unavailable: 'hold — no OFAC data was returned; nothing was screened',
  needs_review: 'hold — the status text was not recognized by this application',
};

await withFixtureApi(async client => {
  const cases = [
    ['no match', FIXTURE_EINS.publicCharity],
    ['possible match', FIXTURE_EINS.ofacMatch],
    ['null status', FIXTURE_EINS.ofacUnavailable],
    ['source not returned', FIXTURE_EINS.sparseIdentity],
  ];

  for (const [label, ein] of cases) {
    const { nonprofit } = await client.nonprofits.check(ein);

    if (!nonprofit) {
      console.log(`No record for ${ein}.`);
      continue;
    }

    const finding = classifyOfac(nonprofit);

    heading(`${label} — ${nonprofit.organization_name}`);
    field('ofac_status', finding.status);
    field('ofac_list_published_date', finding.publishedDate);
    field('getOfac() returned', getOfac(nonprofit) === null ? 'null (no OFAC fields)' : 'an object');
    field('state', finding.state);
    field('routed to', ROUTING[finding.state]);
  }
});

note(
  'Today the API substitutes the "NOT included" sentence when it has no OFAC value,\n' +
    'so the null and unavailable branches are defensive. They still belong in your\n' +
    'code: an absent screening result must never arrive at your approve path.\n\n' +
    'A no-match result is a screening outcome from one list on one date. It is not\n' +
    'sanctions clearance, and it does not cover any other watchlist you are obliged\n' +
    'to check.',
);
