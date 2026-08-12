/**
 * EX-21 — Billing-cycle usage tracking.
 *
 * `nonprofit_check_count`, surfaced as `result.checkCount`, is the running total
 * of checks your account has consumed **so far in the current billing cycle**.
 * It resets to zero when a new cycle starts.
 *
 * It is NOT the size of the request you just made. A bulk call for five EINs
 * does not return 5; it returns your cycle total including those five. Read it
 * as a gauge, and take the size of a request from the request.
 *
 * Run:  PACTMAN_API_KEY=... node examples/ex-21-usage-tracking.mjs
 */
import { FIXTURE_EINS, withFixtureApi } from './lib/fixture-api.mjs';
import { bullet, field, heading, note } from './lib/print.mjs';

/** What an admin screen or a metrics exporter would hold. */
const telemetry = {
  cycleTotal: null,
  observedAt: null,
  samples: [],
};

function record(label, requested, result) {
  const previous = telemetry.cycleTotal;

  telemetry.cycleTotal = result.checkCount;
  telemetry.observedAt = new Date().toISOString();
  telemetry.samples.push({
    label,
    requested,
    cycleTotal: result.checkCount,
    delta: previous === null || result.checkCount === null ? null : result.checkCount - previous,
    requestId: result.requestId,
  });
}

await withFixtureApi(async client => {
  const first = await client.nonprofits.check(FIXTURE_EINS.publicCharity);
  record('single check', 1, first);

  const second = await client.nonprofits.check(FIXTURE_EINS.publicCharitySecond);
  record('single check', 1, second);

  const bulk = await client.nonprofits.checkBulk([
    FIXTURE_EINS.publicCharity,
    FIXTURE_EINS.publicCharitySecond,
    FIXTURE_EINS.privateFoundation,
  ]);
  record('bulk check', 3, bulk);

  const withMisses = await client.nonprofits.checkBulk([
    FIXTURE_EINS.revoked,
    FIXTURE_EINS.noRecord,
  ]);
  record('bulk with a miss', 2, withMisses);

  heading('nonprofit_check_count across four requests');
  console.log(`  ${'request'.padEnd(20)} ${'EINs sent'.padEnd(11)} ${'cycle total'.padEnd(13)} delta`);

  for (const sample of telemetry.samples) {
    console.log(
      `  ${sample.label.padEnd(20)} ${String(sample.requested).padEnd(11)}` +
        ` ${String(sample.cycleTotal).padEnd(13)} ${sample.delta ?? '—'}`,
    );
  }

  heading('Reading the numbers');
  bullet('The cycle total climbs across requests. It is cumulative, not per-request.');
  bullet('The delta is what a request consumed — derive it, or count what you sent.');
  bullet('EINs with no record are not billed, so a delta can be smaller than the batch.');
  bullet('At the start of a new billing cycle this counter resets to zero.');

  heading('Operational surface');
  field('checks used this cycle', telemetry.cycleTotal);
  field('observed at', telemetry.observedAt);
  field('last requestId', telemetry.samples.at(-1)?.requestId);

  // Alerting on the cycle total needs your plan's allowance, which the check
  // endpoints do not report. Keep it in your own configuration.
  const planAllowance = Number(process.env.PACTMAN_PLAN_ALLOWANCE ?? 0);

  if (planAllowance > 0) {
    const used = telemetry.cycleTotal ?? 0;
    field('plan allowance', planAllowance);
    field('utilisation', `${Math.round((used / planAllowance) * 100)}%`);
    field('alert', used / planAllowance > 0.8 ? 'over 80% of the cycle allowance' : 'nominal');
  } else {
    bullet('Set PACTMAN_PLAN_ALLOWANCE to compute utilisation against your plan.');
  }
});

note(
  'Label this metric "checks used this billing cycle" wherever it is displayed.\n' +
    'Labelling it "checks in this request" makes a dashboard that resets monthly\n' +
    'look like a dashboard that is broken.',
);
