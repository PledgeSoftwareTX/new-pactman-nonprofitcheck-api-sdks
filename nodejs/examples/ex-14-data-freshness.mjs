/**
 * EX-14 — Data freshness and report metadata.
 *
 * Every source on the response carries its own date. A check is a statement
 * about the data as of those dates — not as of the moment you called.
 *
 * This example surfaces each timestamp, computes an age, and applies a re-review
 * rule the application owns. The SDK supplies the dates and nothing else: there
 * is no `isStale` property and no default threshold, because 90 days is prudent
 * for one workflow and reckless for another.
 *
 * Run:  PACTMAN_API_KEY=... node examples/ex-14-data-freshness.mjs
 */
import { FIXTURE_EINS, withFixtureApi } from './lib/fixture-api.mjs';
import { bullet, field, heading, note } from './lib/print.mjs';

/** The application's own rule. Change it here, in one place. */
const RE_REVIEW_AFTER_DAYS = 90;

function parseApiDate(value) {
  if (!value) {
    return null;
  }

  const parsed = new Date(value);

  return Number.isNaN(parsed.getTime()) ? null : parsed;
}

function ageInDays(value, now) {
  const parsed = parseApiDate(value);

  return parsed === null ? null : Math.round((now.getTime() - parsed.getTime()) / 86_400_000);
}

function timestampsOf(nonprofit) {
  return {
    organization_info_last_modified: nonprofit.organization_info_last_modified,
    report_date: nonprofit.report_date,
    most_recent_bmf: nonprofit.most_recent_bmf,
    most_recent_pub78: nonprofit.most_recent_pub78,
    ofac_list_published_date: nonprofit.ofac_list_published_date,
    aroe_list_published_date: nonprofit.aroe_list_published_date,
  };
}

await withFixtureApi(async client => {
  const cases = [
    ['recently refreshed', FIXTURE_EINS.publicCharity],
    ['every source is old', FIXTURE_EINS.staleData],
    ['some dates were not returned', FIXTURE_EINS.sparseIdentity],
  ];

  for (const [label, ein] of cases) {
    const result = await client.nonprofits.check(ein);

    if (!result.nonprofit) {
      console.log(`No record for ${ein}.`);
      continue;
    }

    const { nonprofit } = result;
    const now = new Date();
    const timestamps = timestampsOf(nonprofit);

    heading(`${label} — ${nonprofit.organization_name}`);

    for (const [name, value] of Object.entries(timestamps)) {
      const age = ageInDays(value, now);

      console.log(
        `  ${name.padEnd(34)} ${String(value ?? '<null>').padEnd(26)}` +
          ` ${age === null ? 'age unknown' : `${age} days old`}`,
      );
    }

    // `report_date` is when this response was generated. The source dates are
    // when each underlying list was last refreshed. They answer different
    // questions, and the older one governs.
    const ages = Object.entries(timestamps)
      .map(([name, value]) => ({ name, age: ageInDays(value, now) }))
      .filter(entry => entry.age !== null);

    const oldest = ages.reduce(
      (worst, entry) => (worst === null || entry.age > worst.age ? entry : worst),
      null,
    );

    const undated = Object.entries(timestamps)
      .filter(([, value]) => !value)
      .map(([name]) => name);

    if (oldest) {
      bullet(`oldest source: ${oldest.name} at ${oldest.age} days`);
    }

    for (const name of undated) {
      bullet(`no date returned for ${name} — age cannot be established`);
    }

    const needsReReview = (oldest?.age ?? Infinity) > RE_REVIEW_AFTER_DAYS || undated.length > 0;

    field('request timing (timeTaken ms)', result.timeTakenMs);
    field('checked at (local)', now.toISOString());
    field(
      `re-review rule (> ${RE_REVIEW_AFTER_DAYS} days)`,
      needsReReview
        ? 'schedule a re-review — a source is past the threshold or undated'
        : 'within the freshness window — no re-review scheduled',
    );

    // Store the timestamps alongside your verification record, not just the
    // outcome. Six months from now "we checked and it was fine" is not an
    // answer; "we checked on this date against BMF data published on that date"
    // is.
    if (ein === FIXTURE_EINS.publicCharity) {
      console.log('\n  stored with the verification record:');
      console.log(
        JSON.stringify(
          { ein: nonprofit.ein, checkedAt: now.toISOString(), requestId: result.requestId, ...timestamps },
          null,
          2,
        )
          .split('\n')
          .map(line => `    ${line}`)
          .join('\n'),
      );
    }
  }
});

note(
  'A fresh response is not a fresh fact. IRS lists publish on their own schedule,\n' +
    'so a check performed today can reflect a revocation posted weeks ago and not\n' +
    'yet published — see ex-29 for the pre-payment recheck this implies.',
);
