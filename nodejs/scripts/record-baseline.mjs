#!/usr/bin/env node
/**
 * Records the shape of the production API into `src/response-baseline.json`.
 *
 * `src/response-contract.json` says what this package *promises* a response
 * looks like. This file says what production *actually returned*, once, on a
 * day someone looked. They answer different questions and both are needed: the
 * contract catches the API drifting away from the declared types, the baseline
 * catches the API drifting at all — including in the fields the contract leaves
 * as a bare `string`, where a promise is too loose to notice anything.
 *
 * The recording is committed, so it is the same for everyone and a change to it
 * shows up in review as what it is: production moved, and someone accepted it.
 * That is also why writing it is a deliberate command rather than something a
 * smoke run does on the side. A baseline that rewrites itself on every run
 * agrees with the API by construction and can never fail.
 *
 * Usage
 *   node scripts/record-baseline.mjs [--allow-any-target] [--dry-run]
 *
 * The key, the subjects and the target come from the environment or `.env`,
 * exactly as `smoke-live.mjs` reads them. Recording spends billable checks: one
 * single lookup and one bulk lookup against the key you point it at.
 */
import { existsSync, readFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

import {
  DEFAULT_ENVIRONMENT,
  PactmanClient,
  VERSION,
  baseUrlForEnvironment,
  normalizeEin,
  normalizeEins,
} from '@pactmandev/nonprofit-check-plus';
import { signatureOf } from './contract.mjs';
import { API_KEY_ENV, BULK_PROBE_LIMIT, loadEnvFile } from './env.mjs';

const BASELINE_PATH = fileURLToPath(new URL('../src/response-baseline.json', import.meta.url));

const NOTE =
  'The shape production returned when this was recorded: path, JSON type and value format, ' +
  'never a value. Committed, so every run of scripts/smoke-live.mjs is held against the same ' +
  'recording — any path added or removed, and any token that changed, fails there. Rewrite it ' +
  'with `npm run baseline:record` only when production has moved and the move is intended.';

const envFile = loadEnvFile();
const args = process.argv.slice(2);
const allowAnyTarget = args.includes('--allow-any-target');
const dryRun = args.includes('--dry-run');

const apiKey = process.env[API_KEY_ENV];

if (!apiKey) {
  console.error(`No API key. Put ${API_KEY_ENV} in nodejs/.env, or export it, and run this again.`);
  process.exit(2);
}

/** Replaces the credential wherever it surfaces. Applied to everything printed. */
function redact(value) {
  return String(value).split(apiKey).join('[redacted]');
}

function say(...parts) {
  console.log(parts.map(part => redact(part)).join(' '));
}

const productionUrl = baseUrlForEnvironment(DEFAULT_ENVIRONMENT);
const baseUrl = process.env.PACTMAN_BASE_URL ?? productionUrl;

// The baseline every run is held against has to come from the deployment those
// runs are about. A recording made against a sandbox would quietly turn the
// sandbox into the standard, and nothing downstream could tell.
if (normalizeUrl(baseUrl) !== normalizeUrl(productionUrl) && !allowAnyTarget) {
  console.error(
    `Refusing to record from ${baseUrl}.\n` +
      `The committed baseline describes production (${productionUrl}); recording it from ` +
      'anywhere else makes that deployment the standard for everyone.\n' +
      'Unset PACTMAN_BASE_URL, or pass --allow-any-target if you mean it.',
  );
  process.exit(2);
}

function normalizeUrl(value) {
  return value.replace(/\/+$/, '').toLowerCase();
}

if (!process.env.PACTMAN_SMOKE_EIN) {
  console.error('No subject. Set PACTMAN_SMOKE_EIN to the EIN this recording should be made from.');
  process.exit(2);
}

let ein;
let bulkEins;
let missingEin;

try {
  ein = normalizeEin(process.env.PACTMAN_SMOKE_EIN);
  // The same batch `smoke-live.mjs` sends, so the two signatures describe the
  // same set of organizations rather than differing by batch size.
  missingEin = process.env.PACTMAN_SMOKE_MISSING_EIN
    ? normalizeEin(process.env.PACTMAN_SMOKE_MISSING_EIN)
    : null;
  bulkEins = normalizeEins(
    (process.env.PACTMAN_SMOKE_BULK_EIN ?? '')
      .split(',')
      .map(one => one.trim())
      .filter(Boolean)
      .slice(0, BULK_PROBE_LIMIT),
  );
} catch (error) {
  console.error(error instanceof Error ? error.message : String(error));
  process.exit(2);
}

const client = new PactmanClient({ apiKey, baseUrl, timeoutMs: 20_000, retry: { maxRetries: 2 } });

/**
 * The batches to try, in the order `smoke-live.mjs` would arrive at them.
 *
 * That run keeps the first bulk response any of its probes returns, and the
 * probes go in a fixed order: the partial-success batch first, because its
 * envelope is the only one carrying the item-level `errors` a batch with a miss
 * comes back with, then the duplicate probe, which is what a key whose bulk
 * EINs are allowlisted falls back to — such a key refuses the whole batch the
 * moment an EIN with no record is in it.
 *
 * Recording a batch the run will never send would disagree with every run on
 * batch composition alone, and report the difference as the API moving.
 */
const bulkAttempts = [];

if (bulkEins.length > 0 && missingEin) {
  bulkAttempts.push([...bulkEins, missingEin]);
}

if (bulkEins.length >= 2) {
  bulkAttempts.push([bulkEins[1], bulkEins[0], bulkEins[1]]);
}

say(`Target        ${baseUrl}`);
say(`Subjects      ${ein}${bulkEins.length > 0 ? ` · bulk ${bulkEins.join(', ')}` : ' · no bulk subjects'}`);
say(`Cost          up to ${1 + bulkAttempts.length} billable request(s)`);
say('');

/** Runs one lookup and reduces it to a signature, or reports why it could not. */
async function record(label, call) {
  try {
    const result = await call();

    if (result?.raw === undefined) {
      say(`  ${label.padEnd(8)} no response body to record`);

      return null;
    }

    const signature = signatureOf(result.raw);

    say(`  ${label.padEnd(8)} ${Object.keys(signature).length} paths`);

    return signature;
  } catch (error) {
    say(`  ${label.padEnd(8)} failed — ${redact(error instanceof Error ? error.message : error)}`);

    return null;
  }
}

const single = await record('single', () => client.nonprofits.check(ein));

let bulk = null;

for (const attempt of bulkAttempts) {
  bulk = await record('bulk', () => client.nonprofits.checkBulk(attempt));

  if (bulk) {
    break;
  }
}

if (!single && !bulk) {
  console.error('\nNothing was recorded. The baseline on disk is unchanged.');
  process.exit(1);
}

/**
 * A half that could not be recorded keeps whatever is already on disk.
 *
 * A key whose allowlist refuses the batch, or a lookup that timed out, is a
 * reason to record nothing new — not a reason to throw away a good recording
 * made on a day the call worked. Overwriting it with null would delete the
 * standard the bulk checks are held against, and the run that noticed would be
 * the one that stopped failing.
 */
const existing = existsSync(BASELINE_PATH)
  ? JSON.parse(readFileSync(BASELINE_PATH, 'utf8'))
  : {};

const kept = [];

function half(kind, recorded) {
  if (recorded) {
    return { signature: recorded };
  }

  if (existing[kind]?.signature) {
    kept.push(kind);
  }

  return existing[kind] ?? null;
}

const baseline = {
  note: NOTE,
  recordedAt: new Date().toISOString(),
  baseUrl,
  sdkVersion: VERSION,
  single: half('single', single),
  bulk: half('bulk', bulk),
};

if (dryRun) {
  say('\n--dry-run: nothing written.');
  process.exit(0);
}

writeFileSync(BASELINE_PATH, `${JSON.stringify(baseline, null, 2)}\n`);

say(`\nWrote src/response-baseline.json — recorded from ${baseUrl} on SDK ${VERSION}.`);

if (kept.length > 0) {
  say(`The ${kept.join(' and ')} half was left as it was — this run could not record it.`);
}

say('Commit it. Every smoke run from now on is held against it.');
