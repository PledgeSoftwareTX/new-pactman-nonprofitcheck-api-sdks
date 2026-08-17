#!/usr/bin/env node
/**
 * Contract smoke test against a live Nonprofit Check Plus deployment.
 *
 * The mock server in `mock-server.mjs` proves the SDK behaves against a stub the
 * SDK's own authors wrote. This proves it behaves against the real thing.
 *
 * Coverage tracks the documented examples: every claim `examples/ex-01` through
 * `examples/ex-30` makes about the live API has a check here. Most of them cost
 * nothing — a claim about the shape of a record is answered by a record already
 * fetched, and a claim about local validation is answered without sending
 * anything. Only a handful of checks need their own round trip.
 *
 * The report is grouped the same way: one heading per example file, and under it
 * the checks that stand behind what that file claims. Checks run in dependency
 * order rather than example order — a record has to be fetched before anything
 * can be asserted about it, and the log of what went on the wire is only
 * complete at the end — so nothing prints until the run is over. The ticker is
 * what says it is alive in the meantime.
 *
 * IT SPENDS REAL QUOTA. Every billable check is charged against the account
 * behind the key. There is nothing to opt into: one command runs the whole plan,
 * the disruptive probes included, and what it will cost is printed as it starts.
 *
 * Usage
 *   node scripts/smoke-live.mjs <ein> <bulk-eins> <missing-ein>
 *
 * The subjects default to the organizations named below, and are replaced on the
 * command line for a key whose allowlist holds different ones; `--help` prints
 * the whole interface. The key is read from PACTMAN_API_KEY, in the environment
 * or in `nodejs/.env`; PACTMAN_BASE_URL aims the run at a deployment other than
 * production, which is how it is run against the mock server.
 */
import { existsSync, readFileSync, readdirSync, writeFileSync } from 'node:fs';
import { basename } from 'node:path';
import { fileURLToPath } from 'node:url';
import { inspect } from 'node:util';
import * as sdk from '@pactmandev/nonprofit-check-plus';
import {
  BULK_CHECK_PATH,
  DEFAULT_ENVIRONMENT,
  DEFAULT_TIMEOUT_MS,
  EIN_LENGTH,
  MAX_BULK_EINS,
  PactmanApiError,
  PactmanAuthenticationError,
  PactmanAuthorizationError,
  PactmanBadRequestError,
  PactmanClient,
  PactmanConfigurationError,
  PactmanError,
  PactmanErrorCategory,
  PactmanErrorOrigin,
  PactmanNetworkError,
  PactmanNotFoundError,
  PactmanRateLimitError,
  PactmanServerError,
  PactmanTimeoutError,
  PactmanValidationError,
  SINGLE_CHECK_PATH,
  VERSION,
  baseUrlForEnvironment,
  getAroe,
  getBmf,
  getOfac,
  getPub78,
  isPactmanError,
  isValidEin,
  normalizeEin,
  normalizeEins,
  supportedEnvironments,
} from '@pactmandev/nonprofit-check-plus';
import {
  formatChanges,
  schemaDiff,
  signatureOf,
  summarizeChanges,
  typeDiff,
} from './contract.mjs';
import { KNOWN_NONPROFIT_FIELDS } from './fixtures.mjs';

/**
 * The organizations this harness checks.
 *
 * A primary subject with a record, a batch to give the bulk, order and duplicate
 * probes something to work with, and a well-formed EIN with no record for the
 * not-found and partial-success paths.
 *
 * None of them are written down here. A key carries its own allowlist, so which
 * organizations are reachable is a property of whoever is running this, and a
 * default would only mean spending their quota on an EIN their key may not even
 * reach — reported as the deployment's failure rather than the wrong subject.
 * Each is given on the command line, in this order, or in the environment
 * beside the key.
 */
const SUBJECTS = [
  {
    name: 'ein',
    variable: 'PACTMAN_SMOKE_EIN',
    purpose: 'the single check, and every check that reads the record it returns',
  },
  {
    name: 'bulk-eins',
    variable: 'PACTMAN_SMOKE_BULK_EIN',
    purpose: 'comma-separated, two or more, for the batch, order and duplicate probes',
    // The bulk probes read the first three; the rest would cost quota unspent.
    list: { min: 2, max: 3 },
  },
  {
    name: 'missing-ein',
    variable: 'PACTMAN_SMOKE_MISSING_EIN',
    purpose: 'well-formed with no record, for the not-found paths',
  },
];

const USAGE = [
  `Usage: node scripts/smoke-live.mjs ${SUBJECTS.map(({ name }) => `<${name}>`).join(' ')}`,
  '',
  ...SUBJECTS.map(
    ({ name, variable, purpose }) => `  ${name.padEnd(14)}${purpose}\n  ${''.padEnd(14)}or ${variable}`,
  ),
  '',
  'The key is read from PACTMAN_API_KEY, in the environment or in nodejs/.env.',
  'PACTMAN_BASE_URL aims the run at a deployment other than production.',
].join('\n');

/**
 * The subjects for this run, normalized, with where each one came from.
 *
 * A missing or malformed EIN stops the run here rather than at the first
 * request. The alternative is spending quota on a lookup that was never going to
 * match and then reading the failure as the deployment's. Every problem is
 * reported at once, so a run is not corrected one argument per attempt.
 */
function resolveSubjects(args, envFile) {
  if (args.includes('-h') || args.includes('--help')) {
    console.log(USAGE);
    process.exit(0);
  }

  if (args.length > SUBJECTS.length) {
    console.error(`This takes ${SUBJECTS.length} arguments; ${args.length} were given.\n\n${USAGE}`);
    process.exit(2);
  }

  const resolved = [];
  const problems = [];

  SUBJECTS.forEach(({ name, variable, list }, index) => {
    const fromArgs = args[index];
    const given = (fromArgs ?? process.env[variable])?.trim();

    if (!given) {
      problems.push(`<${name}> was not given, and ${variable} is not set`);

      return;
    }

    const parts = (list ? given.split(',') : [given]).map(part => part.trim());
    const malformed = parts.filter(part => !isValidEin(part));

    if (malformed.length > 0) {
      problems.push(
        `${malformed.map(part => `"${part}"`).join(', ')} in <${name}> ` +
          `${malformed.length === 1 ? 'is not a well-formed EIN' : 'are not well-formed EINs'}`,
      );

      return;
    }

    if (list && parts.length < list.min) {
      problems.push(
        `<${name}> holds ${parts.length} EIN; the order and duplicate probes need at least ${list.min}`,
      );

      return;
    }

    // Normalized here so every check downstream compares canonical forms; the
    // ones that prove normalization works build their own hyphenated input.
    const eins = parts.map(part => normalizeEin(part));

    resolved.push({
      value: list ? eins.slice(0, list.max) : eins[0],
      ignored: list ? eins.slice(list.max) : [],
      source:
        fromArgs !== undefined
          ? 'the command line'
          : envFile?.names.has(variable)
            ? basename(envFile.path)
            : 'the environment',
    });
  });

  if (problems.length > 0) {
    console.error(`${problems.join('\n')}\n\n${USAGE}`);
    process.exit(2);
  }

  return resolved;
}

/** The variable the credential is read from, in the environment or in `.env`. */
const API_KEY_ENV = 'PACTMAN_API_KEY';

/** Sent where a key is meant to be rejected. Synthetic, so it cannot be valid. */
const INVALID_API_KEY = 'pactman-smoke-test-invalid-key';

/** Ceiling on the burst the rate-limit probe is allowed to send. */
const RATE_LIMIT_ATTEMPTS = 10;

// --- environment file -------------------------------------------------------

/**
 * Loads `nodejs/.env`, so the key and any standing overrides live in a file
 * rather than in the shell for every run. The file is gitignored.
 *
 * A variable already in the environment wins: exporting one for a single run
 * must not be silently overridden by a file someone set up months ago.
 */
function loadEnvFile() {
  const path = fileURLToPath(new URL('../.env', import.meta.url));

  if (!existsSync(path)) {
    return null;
  }

  const names = new Set();

  for (const line of readFileSync(path, 'utf8').split('\n')) {
    const match = line.match(/^\s*(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)$/);

    if (!match) {
      continue;
    }

    const [, name, rawValue] = match;

    if (process.env[name] !== undefined) {
      continue;
    }

    process.env[name] = rawValue.trim().replace(/^(['"])([\s\S]*)\1$/, '$2');
    names.add(name);
  }

  return { path, names };
}

// --- secret handling --------------------------------------------------------

const secrets = new Set();

/** Replaces every known credential with a placeholder. Applied to all output. */
function redact(value) {
  let text = typeof value === 'string' ? value : inspect(value, { depth: 4 });

  for (const secret of secrets) {
    if (secret && secret.length >= 4) {
      text = text.split(secret).join('[redacted]');
    }
  }

  return text;
}

function say(...parts) {
  console.log(parts.map(part => redact(String(part))).join(' '));
}

/** Where the credential came from, named precisely enough to correct. */
function keySource(envFile) {
  return envFile?.names.has(API_KEY_ENV)
    ? `${API_KEY_ENV} in ${basename(envFile.path)}`
    : API_KEY_ENV;
}

// --- the examples this harness answers for ----------------------------------

const EXAMPLES_DIR = new URL('../examples/', import.meta.url);

/**
 * The checks that are not answering for an example file. The response contract
 * is the API's own shape held against a recording of it — drift there is not
 * something any example claims, and it gets its own heading rather than being
 * filed under one.
 */
const CONTRACT_GROUP = {
  id: 'contract',
  title: 'the live response held against the recorded baseline',
};

const NUMBERED = /^ex-\d{2}-/;

/** Reading order for the unnumbered originals; anything else follows, by name. */
const ORIGINALS = ['quickstart.mjs', 'bulk.mjs', 'error-handling.mjs'];

function rank(file) {
  const index = ORIGINALS.indexOf(file);

  return index === -1 ? ORIGINALS.length : index;
}

/** The title a file gives itself: its `EX-NN —` line, or its opening sentence. */
function titleOf(file, fallback) {
  try {
    const header = readFileSync(new URL(file, EXAMPLES_DIR), 'utf8').slice(0, 600);
    const titled =
      header.match(/EX-\d{2}\s+—\s+([^\n]+?)\.?\s*$/m) ??
      header.match(/^\s*\*\s+(\S[^\n]*?)\.?\s*$/m);

    if (titled) {
      return titled[1];
    }
  } catch {
    // The slug is a serviceable title.
  }

  return fallback;
}

/**
 * Every example in `examples/`, in reading order, with the title it gives itself.
 *
 * The unnumbered originals come first: `quickstart`, `bulk` and `error-handling`
 * are the shortest form of what the numbered files elaborate, and they are what
 * anyone runs before anything else, so they are what the report opens with.
 *
 * Read from disk rather than listed here, so an example added tomorrow appears
 * in the report on its own — with no check under it, which is the state worth
 * seeing.
 */
function discoverExamples() {
  let files;

  try {
    files = readdirSync(EXAMPLES_DIR)
      .filter(name => name.endsWith('.mjs'))
      .sort();
  } catch {
    return [];
  }

  const originals = files
    .filter(name => !NUMBERED.test(name))
    .sort((left, right) => rank(left) - rank(right) || left.localeCompare(right));

  const ordered = [...originals, ...files.filter(name => NUMBERED.test(name))];

  return ordered.map(file => {
    const numbered = NUMBERED.test(file);
    const id = numbered ? file.slice(0, 5) : file.slice(0, -4);
    const slug = numbered ? file.slice(6, -4).replace(/-/g, ' ') : id.replace(/-/g, ' ');

    return { id, title: titleOf(file, slug), file };
  });
}

/**
 * The headings, in reading order, with every check filed under the examples it
 * covers.
 *
 * A check is listed in full under the first example it covers and cross-
 * referenced under the rest: it ran once, so it is counted once, but an example
 * whose claim is proven by a check that lives elsewhere still says so under its
 * own heading rather than looking untested.
 */
function groupByExample(examples, entries) {
  const groups = new Map(
    [...examples, CONTRACT_GROUP].map(example => [
      example.id,
      { ...example, primary: [], secondary: [] },
    ]),
  );

  const groupFor = id => {
    if (!groups.has(id)) {
      // A check naming something the examples directory does not have. Give it a
      // heading anyway; a result must never fall out of the report.
      groups.set(id, { id, title: 'no example file of this name', primary: [], secondary: [] });
    }

    return groups.get(id);
  };

  for (const entry of entries) {
    const [primary, ...rest] = entry.covers;

    groupFor(primary).primary.push(entry);

    for (const id of rest) {
      groupFor(id).secondary.push({ entry, under: primary });
    }
  }

  return [...groups.values()];
}

// --- the runner -------------------------------------------------------------

const STATUS = { pass: '✓', fail: '✗', warn: '!', skip: '–' };

class Runner {
  constructor(apiKey) {
    this.apiKey = apiKey;
    this.results = [];
    this.findings = [];
    this.checksSpent = 0;
    this.requestsSent = 0;
    this.cycleCountStart = null;
    this.cycleCountEnd = null;
    /** One entry per outbound request, with the credential reduced to a flag. */
    this.requests = [];
  }

  /** Records an observation that is informative but not a pass/fail. */
  note(check, message) {
    this.findings.push({ check, message });
  }

  /**
   * Captures what went on the wire. The Authorization value is reduced to a
   * boolean here rather than stored, so no code path downstream can print it.
   */
  recordRequest(input, init) {
    this.requestsSent += 1;

    const url = String(input);
    const headers = new Headers(init?.headers ?? {});
    const authorization = headers.get('authorization') ?? '';

    this.requests.push({
      method: init?.method ?? 'GET',
      url,
      urlCarriesKey: url.includes(this.apiKey),
      authCarriesKey: authorization.includes(this.apiKey),
      authScheme: authorization.split(' ')[0] ?? '',
      accept: headers.get('accept'),
      contentType: headers.get('content-type'),
      userAgent: headers.get('user-agent'),
      body: typeof init?.body === 'string' ? init.body : null,
    });
  }

  async run(definition) {
    const { covers, name, cost = 0, body } = definition;
    const startedAt = Date.now();

    try {
      const outcome = (await body(this)) ?? {};

      this.checksSpent += cost;
      this.results.push({
        covers,
        name,
        status: outcome.status ?? 'pass',
        detail: outcome.detail ?? '',
        data: outcome.data,
        cost,
        durationMs: Date.now() - startedAt,
      });

      return outcome.value ?? null;
    } catch (error) {
      // A failed check may still have been billed, so the cost stands.
      this.checksSpent += cost;
      this.results.push({
        covers,
        name,
        status: 'fail',
        detail: redact(error instanceof Error ? error.message : String(error)),
        errorClass: error?.constructor?.name ?? typeof error,
        cost,
        durationMs: Date.now() - startedAt,
      });

      return null;
    }
  }

  /**
   * Keeps the first successful bulk response for the checks that read one.
   *
   * `bulk partial success` is the better subject — its envelope is the only one
   * carrying the item-level errors a batch with a miss returns — but it is
   * unreachable on a key whose bulk EINs are allowlisted, since such a key
   * refuses the whole batch. Capturing here rather than in that one check means
   * the duplicate probe's response stands in when it has to, instead of four
   * later checks skipping for want of any bulk response at all.
   */
  captureBulk(result, submitted) {
    if (!this.bulkResult) {
      this.bulkResult = result;
      this.bulkSubmitted = submitted;
    }
  }

  /** Tracks the cumulative counter across the whole run. */
  observeCycleCount(value) {
    if (typeof value !== 'number') {
      return;
    }

    if (this.cycleCountStart === null) {
      this.cycleCountStart = value;
    }

    this.cycleCountEnd = value;
  }
}

function assert(condition, message) {
  if (!condition) {
    throw new Error(message);
  }
}

/**
 * True when a 404 came from the free-tier EIN allowlist rather than from an
 * absent record.
 *
 * A free key carries a fixed set of accessible EINs. The server requires every
 * EIN in a bulk body to be on that list and answers 404 for the whole batch
 * otherwise, before any lookup runs — so partial success cannot be reached with
 * such a key. That is a property of the key, not of the deployment, and the
 * checks it makes unreachable are skipped rather than failed.
 */
function isFreeTierRestriction(error) {
  return (
    error instanceof PactmanNotFoundError &&
    (error.apiErrors ?? []).some(detail => /accessible nonprofits/i.test(String(detail?.reason)))
  );
}

// --- small helpers ----------------------------------------------------------

/** True when the API returned the field at all, `null` included. */
function returned(nonprofit, field) {
  return field in nonprofit && nonprofit[field] !== undefined;
}

/** `present` | `null` | `absent` — the three outcomes ex-05 turns on. */
function presence(nonprofit, field) {
  if (!returned(nonprofit, field)) {
    return 'absent';
  }

  return nonprofit[field] === null ? 'null' : 'present';
}

function parseApiDate(value) {
  if (typeof value !== 'string' || value.trim() === '') {
    return null;
  }

  const timestamp = Date.parse(value);

  return Number.isNaN(timestamp) ? null : timestamp;
}

function ageInDays(timestamp, now = Date.now()) {
  return Math.round((now - timestamp) / 86_400_000);
}

function truncate(value, length = 60) {
  const text = String(value);

  return text.length <= length ? text : `${text.slice(0, length - 1)}…`;
}

/** Marker proving a call reached the transport instead of failing validation. */
class ReachedTransport extends Error {}

function reachedTransport(error) {
  return error instanceof PactmanNetworkError && error.cause instanceof ReachedTransport;
}

// --- check builders ---------------------------------------------------------

/**
 * A zero-cost check over the record the single check already fetched.
 *
 * This is what keeps coverage affordable: most of what the examples claim is a
 * claim about a response, and one response answers all of them.
 */
function fromRecord(covers, name, body) {
  return {
    covers,
    name,
    cost: 0,
    body(runner) {
      const nonprofit = runner.singleResult?.nonprofit;

      if (!nonprofit) {
        return { status: 'skip', detail: 'the single check returned no record' };
      }

      return body(nonprofit, runner);
    },
  };
}

/**
 * Checks that a grouped source view is a projection and nothing more: every
 * property copied 1:1 from the field the API returned, nothing invented, and
 * `null` returned only when the source is genuinely absent.
 */
function sourceProjection({ covers, name, get, mapping, absentStatus = 'warn', describe }) {
  return fromRecord(covers, name, (nonprofit, runner) => {
    const projected = get(nonprofit);
    const wireFields = Object.values(mapping).filter(field => returned(nonprofit, field));

    if (projected === null) {
      assert(
        wireFields.length === 0,
        `the projection was null while the API returned ${wireFields.length} of its fields`,
      );

      runner.note(name, 'the API returned nothing for this source — an absence, not a negative');

      return { status: absentStatus, detail: 'not returned for this record' };
    }

    for (const [target, wireField] of Object.entries(mapping)) {
      const onWire = returned(nonprofit, wireField);

      assert(
        onWire === (target in projected),
        `"${target}" and the wire field "${wireField}" disagree about presence`,
      );

      if (onWire) {
        assert(
          Object.is(projected[target], nonprofit[wireField]),
          `"${target}" is not the value the API returned in "${wireField}"`,
        );
      }
    }

    const invented = Object.keys(projected).filter(key => !(key in mapping));

    assert(invented.length === 0, `the projection added fields the API did not send: ${invented.join(', ')}`);

    return {
      detail: `${wireFields.length}/${Object.keys(mapping).length} fields returned · ${describe(projected)}`,
      data: projected,
    };
  });
}

// --- checks: the client itself (ex-01) --------------------------------------

function clientChecks(apiKey) {
  return [
    {
      covers: ['ex-01'],
      name: 'configuration and redaction',
      cost: 0,
      body(runner) {
        const client = runner.client;

        assert(typeof client.baseUrl === 'string', 'client.baseUrl is not a string');
        assert(client.timeoutMs > 0 && Number.isFinite(client.timeoutMs), 'timeout is not finite');

        // The credential must not be reachable from any diagnostic surface.
        const surfaces = [
          inspect(client, { depth: 5 }),
          JSON.stringify(client),
          client.toString(),
          `${client}`,
        ];

        for (const surface of surfaces) {
          assert(!surface.includes(apiKey), 'the API key appeared in a diagnostic surface');
        }

        assert(
          JSON.parse(JSON.stringify(client)).apiKey === '[redacted]',
          'toJSON did not replace the key with a placeholder',
        );

        return { detail: `${client.baseUrl} · timeout ${client.timeoutMs}ms · SDK ${VERSION}` };
      },
    },

    {
      covers: ['ex-01'],
      name: 'configuration is validated',
      cost: 0,
      body() {
        const rejected = [
          ['no options object', () => new PactmanClient()],
          ['a missing key', () => new PactmanClient({})],
          ['a blank key', () => new PactmanClient({ apiKey: '   ' })],
          ['a non-string key', () => new PactmanClient({ apiKey: 1234 })],
          ['a malformed base URL', () => new PactmanClient({ apiKey, baseUrl: 'not a url' })],
          ['a non-HTTP base URL', () => new PactmanClient({ apiKey, baseUrl: 'ftp://example.org' })],
          ['a zero timeout', () => new PactmanClient({ apiKey, timeoutMs: 0 })],
          ['an infinite timeout', () => new PactmanClient({ apiKey, timeoutMs: Infinity })],
          ['a negative retry count', () => new PactmanClient({ apiKey, retry: { maxRetries: -1 } })],
          ['an unknown environment', () => new PactmanClient({ apiKey, environment: 'staging' })],
        ];

        for (const [description, construct] of rejected) {
          try {
            construct();
            throw new Error(`${description} was accepted`);
          } catch (error) {
            assert(
              error instanceof PactmanConfigurationError,
              `${description}: expected PactmanConfigurationError, got ${error?.constructor?.name}`,
            );
          }
        }

        // Defaults, which no example spells out because every example relies on them.
        const defaults = new PactmanClient({ apiKey });

        assert(defaults.timeoutMs === DEFAULT_TIMEOUT_MS, 'the default timeout is not DEFAULT_TIMEOUT_MS');
        assert(
          defaults.baseUrl === baseUrlForEnvironment(DEFAULT_ENVIRONMENT),
          'the default base URL is not the default environment',
        );
        assert(defaults.environment === DEFAULT_ENVIRONMENT, 'the default environment was not reported');
        assert(
          new PactmanClient({ apiKey, baseUrl: 'https://example.org' }).environment === null,
          'an explicit baseUrl should report no named environment',
        );

        return {
          detail:
            `${rejected.length} unusable configurations rejected locally · ` +
            `defaults: ${DEFAULT_TIMEOUT_MS}ms, ${supportedEnvironments().join(', ')}`,
        };
      },
    },

    {
      // The batch limit and the endpoint paths are exports ex-20 tells callers to
      // import rather than copy, so its heading names this check too.
      covers: ['ex-01', 'ex-20'],
      name: 'exported surface',
      cost: 0,
      body() {
        const expected = {
          PactmanClient: 'function',
          NonprofitsResource: 'function',
          PactmanError: 'function',
          PactmanApiError: 'function',
          PactmanAuthenticationError: 'function',
          PactmanAuthorizationError: 'function',
          PactmanBadRequestError: 'function',
          PactmanConfigurationError: 'function',
          PactmanNetworkError: 'function',
          PactmanNotFoundError: 'function',
          PactmanRateLimitError: 'function',
          PactmanServerError: 'function',
          PactmanTimeoutError: 'function',
          PactmanValidationError: 'function',
          isPactmanError: 'function',
          normalizeEin: 'function',
          normalizeEins: 'function',
          isValidEin: 'function',
          baseUrlForEnvironment: 'function',
          supportedEnvironments: 'function',
          getPub78: 'function',
          getBmf: 'function',
          getAroe: 'function',
          getOfac: 'function',
          VERSION: 'string',
          DEFAULT_ENVIRONMENT: 'string',
          SINGLE_CHECK_PATH: 'string',
          BULK_CHECK_PATH: 'string',
          DEFAULT_TIMEOUT_MS: 'number',
          EIN_LENGTH: 'number',
          MAX_BULK_EINS: 'number',
          PactmanEnvironment: 'object',
          PactmanErrorCategory: 'object',
          PactmanErrorOrigin: 'object',
        };

        const wrong = Object.entries(expected)
          .filter(([name, kind]) => typeof sdk[name] !== kind)
          .map(([name, kind]) => `${name} (expected ${kind}, got ${typeof sdk[name]})`);

        assert(wrong.length === 0, `missing or mistyped exports: ${wrong.join(', ')}`);

        // The server's limits belong to the server; ex-20 asks callers to import
        // them rather than copy the numbers into their own constants.
        assert(Number.isInteger(MAX_BULK_EINS) && MAX_BULK_EINS > 0, 'MAX_BULK_EINS is not a positive integer');
        assert(EIN_LENGTH === 9, `EIN_LENGTH is ${EIN_LENGTH}`);
        assert(/^\d+\.\d+\.\d+/.test(VERSION), `VERSION "${VERSION}" is not semver-shaped`);
        assert(SINGLE_CHECK_PATH.includes('{ein}'), 'SINGLE_CHECK_PATH has no {ein} placeholder');

        return {
          detail: `${Object.keys(expected).length} documented exports present · MAX_BULK_EINS ${MAX_BULK_EINS}`,
        };
      },
    },

    {
      // ex-22 and ex-24 name the classes their probes raise; this is the part of
      // what they claim that costs nothing and runs on every key.
      covers: ['ex-16', 'error-handling', 'ex-22', 'ex-24'],
      name: 'error taxonomy',
      cost: 0,
      body() {
        const init = { status: 0 };
        const cases = [
          [new PactmanBadRequestError('x', init), PactmanErrorCategory.BadRequest, 'api'],
          [new PactmanAuthenticationError('x', init), PactmanErrorCategory.Authentication, 'api'],
          [new PactmanAuthorizationError('x', init), PactmanErrorCategory.Authorization, 'api'],
          [new PactmanNotFoundError('x', init), PactmanErrorCategory.NotFound, 'api'],
          [new PactmanRateLimitError('x', init), PactmanErrorCategory.RateLimit, 'api'],
          [new PactmanServerError('x', init), PactmanErrorCategory.Server, 'api'],
          [new PactmanValidationError('x'), PactmanErrorCategory.Validation, 'local'],
          [new PactmanConfigurationError('x'), PactmanErrorCategory.Configuration, 'local'],
          [new PactmanTimeoutError('x', 1), PactmanErrorCategory.Timeout, 'local'],
          [new PactmanNetworkError('x'), PactmanErrorCategory.Network, 'local'],
        ];

        for (const [error, category, origin] of cases) {
          assert(error instanceof PactmanError, `${error.name} is not a PactmanError`);
          assert(error.category === category, `${error.name} has category "${error.category}"`);
          assert(error.origin === origin, `${error.name} has origin "${error.origin}"`);
          assert(isPactmanError(error), `isPactmanError rejected ${error.name}`);
          assert(error.name === error.constructor.name, `${error.constructor.name} reports name "${error.name}"`);
        }

        // Every API error is catchable as one class; the specific ones stay specific.
        for (const [error] of cases.slice(0, 6)) {
          assert(error instanceof PactmanApiError, `${error.name} is not a PactmanApiError`);
        }

        assert(!isPactmanError(new Error('x')), 'isPactmanError accepted a plain Error');
        assert(
          PactmanErrorOrigin.Local === 'local' && PactmanErrorOrigin.Api === 'api',
          'the origin constants are not the documented strings',
        );

        return { detail: `${cases.length} error classes · category and origin as documented` };
      },
    },

    {
      // Every one of these examples says in prose that the helper it would have
      // been convenient to call does not exist.
      covers: ['ex-04', 'ex-06', 'ex-10', 'ex-14'],
      name: 'no derived verdicts',
      cost: 0,
      body() {
        // The SDK reports what the sources said and stops. Every example says so
        // in prose; this is the executable version.
        const forbidden = [
          'namesMatch',
          'addressesMatch',
          'isExempt',
          'isEligible',
          'isGrantEligible',
          'isDeductible',
          'isRevoked',
          'isReinstated',
          'isSanctioned',
          'isStale',
          'hasOfacMatch',
          'hasConflict',
          'score',
          'verdict',
          'decide',
          'approve',
        ];

        const found = forbidden.filter(name => name in sdk);

        assert(found.length === 0, `the SDK exposes derived verdicts: ${found.join(', ')}`);

        return { detail: `none of ${forbidden.length} verdict helpers exist — policy stays in caller code` };
      },
    },
  ];
}

// --- checks: local validation (ex-02, ex-15, ex-20) -------------------------

function localValidationChecks(ein, apiKey) {
  return [
    {
      covers: ['ex-15', 'error-handling'],
      name: 'malformed input sends nothing',
      cost: 0,
      async body(runner) {
        const before = runner.requestsSent;
        const normalized = normalizeEin(ein);

        // Each one is the subject with a single thing wrong with it, so what is
        // being rejected is that flaw and not some other property of the input.
        const malformed = [
          normalized.slice(0, EIN_LENGTH - 1),
          'not-an-ein',
          '',
          null,
          `${normalized.slice(0, 2)}.${normalized.slice(2)}`,
          Number(normalized),
        ];

        const batches = [
          ['an empty batch', []],
          ['a non-array batch', 'not-an-array'],
          ['a batch with one bad entry', [ein, 'nope']],
        ];

        for (const bad of malformed) {
          try {
            await runner.client.nonprofits.check(bad);
            throw new Error(`"${bad}" was accepted by local validation`);
          } catch (error) {
            assert(
              error instanceof PactmanValidationError,
              `expected PactmanValidationError for ${JSON.stringify(bad)}, got ${error?.constructor?.name}`,
            );
            assert(error.origin === 'local', `a local rejection reported origin "${error.origin}"`);
          }
        }

        for (const [description, input] of batches) {
          try {
            await runner.client.nonprofits.checkBulk(input);
            throw new Error(`${description} was accepted`);
          } catch (error) {
            assert(
              error instanceof PactmanValidationError,
              `${description} did not raise a validation error`,
            );
          }
        }

        const sent = runner.requestsSent - before;

        assert(sent === 0, `${sent} HTTP requests were sent for input that should never leave the process`);

        return {
          detail: `${malformed.length + batches.length} malformed inputs rejected in-process with 0 requests`,
        };
      },
    },

    {
      covers: ['ex-02', 'ex-15', 'ex-18'],
      name: 'EIN helpers',
      cost: 0,
      body() {
        const normalized = normalizeEin(ein);
        const hyphenated = `${normalized.slice(0, 2)}-${normalized.slice(2)}`;

        assert(/^\d{9}$/.test(normalized), `normalizeEin produced "${normalized}"`);
        assert(
          normalizeEin(`  ${hyphenated}  `) === normalized,
          'the hyphenated and padded form did not normalize to the plain one',
        );
        assert(
          isValidEin(normalized) && isValidEin(hyphenated),
          'isValidEin rejected a well-formed EIN',
        );
        assert(
          !isValidEin(normalized.slice(0, EIN_LENGTH - 1)) &&
            !isValidEin(null) &&
            !isValidEin(Number(normalized)),
          'isValidEin accepted a malformed value',
        );

        // Order and duplicates survive normalization; ex-18 depends on it. The
        // second subject is here only as an EIN that is not the first one.
        const other = BULK_EINS[1];
        const supplied = [hyphenated, other, hyphenated];

        assert(
          normalizeEins(supplied).join(',') === [normalized, other, normalized].join(','),
          'normalizeEins reordered or deduplicated its input',
        );

        // Every failure is reported at once, by index, rather than the first one.
        try {
          normalizeEins([hyphenated, 'nope', '', other]);
          throw new Error('normalizeEins accepted two malformed entries');
        } catch (error) {
          assert(error instanceof PactmanValidationError, 'normalizeEins raised the wrong error type');
          assert(error.issues.length === 2, `expected 2 issues, got ${error.issues.length}`);
          assert(
            error.issues.map(issue => issue.index).join(',') === '1,2',
            'the issues did not identify the failing positions',
          );
        }

        return { detail: `${EIN_LENGTH}-digit normalization · order and duplicates preserved · issues by index` };
      },
    },

    {
      covers: ['ex-20', 'bulk'],
      name: 'bulk batch limit is local',
      cost: 0,
      async body(runner) {
        // A fetch that refuses to send. Reaching it proves local validation
        // passed; never reaching it proves the batch was rejected in-process.
        const probe = new PactmanClient({
          apiKey,
          baseUrl: runner.client.baseUrl,
          retry: false,
          fetch: () => {
            throw new ReachedTransport('the request reached the transport');
          },
        });

        // Filler, counted rather than looked up: this probe never sends, so these
        // only have to be well-formed, and no organization needs to exist.
        const filler = index => String(10 ** (EIN_LENGTH - 1) + index);
        const atLimit = Array.from({ length: MAX_BULK_EINS }, (_, i) => filler(i));
        const overLimit = [...atLimit, filler(MAX_BULK_EINS)];

        let reached = false;

        try {
          await probe.nonprofits.checkBulk(atLimit);
        } catch (error) {
          reached = reachedTransport(error);
        }

        assert(reached, `a batch of exactly ${MAX_BULK_EINS} was rejected locally`);

        const before = runner.requestsSent;

        try {
          await probe.nonprofits.checkBulk(overLimit);
          throw new Error(`a batch of ${overLimit.length} was accepted`);
        } catch (error) {
          assert(
            error instanceof PactmanValidationError,
            `an over-limit batch raised ${error?.constructor?.name}`,
          );
          assert(
            error.message.includes(String(MAX_BULK_EINS)),
            'the rejection did not name the limit that was exceeded',
          );
        }

        // `dedupe` collapses before the limit applies, so a duplicate-heavy list
        // that exceeds the limit as supplied still goes out.
        const duplicateHeavy = Array.from({ length: MAX_BULK_EINS + 10 }, (_, i) => filler(i % 10));

        let dedupedReached = false;

        try {
          await probe.nonprofits.checkBulk(duplicateHeavy, { dedupe: true });
        } catch (error) {
          dedupedReached = reachedTransport(error);
        }

        assert(dedupedReached, 'dedupe did not collapse duplicates before the limit was applied');
        assert(
          runner.requestsSent === before,
          'the over-limit batch was sent through the real transport',
        );

        return {
          detail: `${MAX_BULK_EINS} accepted · ${overLimit.length} rejected in-process · dedupe collapses first`,
        };
      },
    },
  ];
}

// --- checks: authentication (ex-01, ex-23) ----------------------------------

function authenticationChecks(ein, baseUrl) {
  /** A client with the invalid key and a fetch we can count. */
  function rejectedClient(retry) {
    const counter = { sent: 0 };
    const client = new PactmanClient({
      apiKey: INVALID_API_KEY,
      baseUrl,
      retry,
      timeoutMs: 15_000,
      fetch: (input, init) => {
        counter.sent += 1;

        return globalThis.fetch(input, init);
      },
    });

    return { client, counter };
  }

  return [
    {
      covers: ['ex-01', 'error-handling'],
      name: 'authentication is enforced',
      cost: 0,
      async body(runner) {
        const { client } = rejectedClient(false);

        try {
          await client.nonprofits.check(ein);

          return {
            status: 'fail',
            detail: 'an invalid key was accepted — check what --invalid-api-key was set to',
          };
        } catch (error) {
          if (error instanceof PactmanAuthenticationError) {
            assert(error.origin === 'api', `expected origin "api", got ${error.origin}`);
            assert(
              !(JSON.stringify(error) + String(error.stack)).includes(INVALID_API_KEY),
              'the rejected key appeared in error diagnostics',
            );

            return { detail: `HTTP ${error.status} → PactmanAuthenticationError` };
          }

          if (error instanceof PactmanApiError) {
            runner.note(
              'authentication is enforced',
              `an invalid key produced HTTP ${error.status} (${error.constructor.name}), not 401`,
            );

            return { status: 'warn', detail: `rejected, but as HTTP ${error.status} rather than 401` };
          }

          throw error;
        }
      },
    },

    {
      covers: ['ex-23'],
      name: 'rejected keys are not retried',
      cost: 0,
      async body(runner) {
        // Retrying a rejected key just burns the same key three times. The policy
        // says 401/403/404 are never retried whatever `retryableStatuses` holds;
        // this is the live proof, counted at the socket.
        const { client, counter } = rejectedClient({
          maxRetries: 2,
          initialDelayMs: 10,
          retryableStatuses: [401, 403, 404, 429, 500],
        });

        let status = null;

        try {
          await client.nonprofits.check(ein);
        } catch (error) {
          status = error instanceof PactmanApiError ? error.status : null;

          if (error instanceof PactmanApiError) {
            assert(error.attempts === 1, `the error reports ${error.attempts} attempts`);
          }
        }

        if (status !== null && ![401, 403, 404].includes(status)) {
          runner.note(
            'rejected keys are not retried',
            `the invalid key produced HTTP ${status}, which is retryable — the no-retry rule was not exercised`,
          );

          return { status: 'warn', detail: `HTTP ${status} after ${counter.sent} request(s)` };
        }

        assert(
          counter.sent === 1,
          `a rejected key was sent ${counter.sent} times with retries on and 401 in retryableStatuses`,
        );

        return { detail: `HTTP ${status ?? 'none'} · 1 request, no retry, even when listed as retryable` };
      },
    },
  ];
}

// --- checks: the single check and its record (ex-02..ex-05, ex-16) ----------

function singleCheckChecks(ein, apiKey) {
  return [
    {
      // The one fetch every record-derived check below reads.
      covers: ['ex-03', 'quickstart', 'ex-26', 'ex-27'],
      name: 'single check',
      cost: 1,
      async body(runner) {
        const sentAt = Date.now();
        const result = await runner.client.nonprofits.check(ein);

        // Recorded so the optional timeout probe can pick a deadline that is
        // shorter than a real round trip but longer than connection setup.
        runner.observedRoundTripMs = Date.now() - sentAt;
        runner.observeCycleCount(result.checkCount);

        assert(result.status === 200, `expected HTTP 200, got ${result.status}`);
        assert(result.nonprofit !== null, `no record returned for ${ein} — EIN needs one that exists`);
        assert(
          result.nonprofit.ein === normalizeEin(ein),
          `response EIN ${result.nonprofit.ein} does not match the normalized request ${normalizeEin(ein)}`,
        );

        runner.singleResult = result;

        return {
          detail: `${result.nonprofit.organization_name} · request ${result.requestId ?? 'no id'}`,
          data: { checkCount: result.checkCount, timeTakenMs: result.timeTakenMs },
        };
      },
    },

    {
      covers: ['ex-03', 'ex-21'],
      name: 'envelope shape',
      cost: 0,
      body(runner) {
        const result = runner.singleResult;

        if (!result) {
          return { status: 'skip', detail: 'the single check did not return a record' };
        }

        const envelopeKeys = Object.keys(result.raw);

        for (const key of ['code', 'message', 'data']) {
          assert(envelopeKeys.includes(key), `the envelope is missing "${key}"`);
        }

        assert(typeof result.raw.code === 'number', `envelope "code" is ${typeof result.raw.code}`);
        assert(Array.isArray(result.errors), 'result.errors was not normalized to an array');
        assert(
          result.checkCount === null || typeof result.checkCount === 'number',
          'checkCount is neither a number nor null',
        );
        assert(
          result.timeTakenMs === null || typeof result.timeTakenMs === 'number',
          'timeTakenMs is neither a number nor null',
        );
        assert(
          result.requestId === null || typeof result.requestId === 'string',
          'requestId is neither a string nor null',
        );

        const missing = ['timeTaken', 'nonprofit_check_count'].filter(key => !envelopeKeys.includes(key));

        if (missing.length > 0) {
          runner.note('envelope shape', `envelope did not include: ${missing.join(', ')}`);
        }

        // A numeric field that arrives as something else reads as `null`, which
        // looks exactly like "not reported" downstream. Say so rather than let
        // the usage checks skip themselves for a reason nobody sees.
        const mistyped = [
          ['nonprofit_check_count', result.raw.nonprofit_check_count, result.checkCount],
          ['timeTaken', result.raw.timeTaken, result.timeTakenMs],
        ].filter(([, wire, parsed]) => wire !== undefined && wire !== null && parsed === null);

        for (const [key, wire] of mistyped) {
          runner.note(
            'envelope shape',
            `"${key}" arrived as ${typeof wire} (${JSON.stringify(wire)}), not a number — it is reported as null`,
          );
        }

        if (result.requestId === null) {
          runner.note('envelope shape', 'no correlation header was returned — audit trails lose the request id');
        }

        return {
          status: missing.length > 0 || mistyped.length > 0 ? 'warn' : 'pass',
          detail:
            `${envelopeKeys.length} envelope keys · code ${result.raw.code} · ` +
            `${result.timeTakenMs ?? '?'}ms server-side` +
            (mistyped.length > 0 ? ` · ${mistyped.length} numeric field(s) mistyped` : ''),
          data: { envelopeKeys },
        };
      },
    },

    fromRecord(['ex-25', 'ex-03'], 'model field coverage', (nonprofit, runner) => {
      // Drift detection. New fields are expected over time and are not failures;
      // they are the reason `raw` and the index signature exist.
      const returnedFields = Object.keys(nonprofit);
      const unknown = returnedFields.filter(key => !KNOWN_NONPROFIT_FIELDS.has(key));
      const absent = [...KNOWN_NONPROFIT_FIELDS].filter(key => !returnedFields.includes(key));

      if (unknown.length > 0) {
        runner.note(
          'model field coverage',
          `fields newer than this SDK: ${unknown.join(', ')} — readable via raw and index access`,
        );
      }

      if (absent.length > 0) {
        runner.note(
          'model field coverage',
          `documented fields not returned for this record: ${absent.join(', ')}`,
        );
      }

      return {
        detail: `${returnedFields.length} fields · ${unknown.length} newer than the SDK · ${absent.length} not returned`,
        data: { unknown, absent },
      };
    }),

    fromRecord(['ex-03'], 'identity fields', (nonprofit, runner) => {
      assert(/^\d{9}$/.test(String(nonprofit.ein)), `ein came back as "${nonprofit.ein}"`);
      assert(
        typeof nonprofit.organization_name === 'string' && nonprofit.organization_name.trim() !== '',
        'organization_name is missing or empty',
      );

      if (typeof nonprofit.pactman_org_url === 'string') {
        try {
          new URL(nonprofit.pactman_org_url);
        } catch {
          runner.note('identity fields', `pactman_org_url is not a URL: ${nonprofit.pactman_org_url}`);
        }
      }

      const modified = parseApiDate(nonprofit.organization_info_last_modified);

      return {
        detail:
          `${nonprofit.ein} · ${truncate(nonprofit.organization_name, 40)}` +
          (modified === null ? '' : ` · modified ${ageInDays(modified)}d ago`),
      };
    }),

    fromRecord(['ex-04'], 'name fields', (nonprofit, runner) => {
      const names = {
        organization_name: nonprofit.organization_name,
        organization_name_aka: nonprofit.organization_name_aka,
        pub78_organization_name: nonprofit.pub78_organization_name,
        bmf_organization_name: nonprofit.bmf_organization_name,
      };

      for (const [field, value] of Object.entries(names)) {
        assert(
          value === undefined || value === null || typeof value === 'string',
          `${field} came back as ${typeof value}`,
        );
      }

      // Each source keeps its own spelling. Differences between them are normal,
      // and reconciling them is the caller's policy (ex-04).
      const spellings = new Set(
        Object.values(names).filter(value => typeof value === 'string' && value.trim() !== ''),
      );

      if (spellings.size > 1) {
        runner.note(
          'name fields',
          `the sources spell the name differently: ${[...spellings].map(name => `"${name}"`).join(' vs ')}`,
        );
      }

      return {
        detail: `${spellings.size} distinct spelling(s) preserved across ${Object.keys(names).length} name fields`,
        data: names,
      };
    }),

    fromRecord(['ex-05'], 'address fields', (nonprofit, runner) => {
      const fields = ['address_line1', 'address_line2', 'city', 'state', 'state_name', 'zip'];
      const states = Object.fromEntries(fields.map(field => [field, presence(nonprofit, field)]));

      // "Returned as null" and "not returned" are different answers, and the SDK
      // must not flatten one into the other (ex-05).
      for (const field of fields) {
        assert(
          !(field in nonprofit) || nonprofit[field] !== undefined,
          `${field} is present but undefined — absent and null were conflated`,
        );
      }

      const unconfirmed = fields.filter(field => states[field] !== 'present');

      if (unconfirmed.length > 0) {
        runner.note(
          'address fields',
          `no value returned for ${unconfirmed.join(', ')} — these components are unconfirmed, not mismatched`,
        );
      }

      return {
        detail: `${fields.length - unconfirmed.length}/${fields.length} components returned with a value`,
        data: states,
      };
    }),

    {
      covers: ['ex-02'],
      name: 'EIN normalization end to end',
      cost: 1,
      async body(runner) {
        const normalized = normalizeEin(ein);
        const hyphenated = `  ${normalized.slice(0, 2)}-${normalized.slice(2)}  `;
        const before = runner.requests.length;
        const result = await runner.client.nonprofits.check(hyphenated);

        runner.observeCycleCount(result.checkCount);

        assert(result.nonprofit !== null, 'the hyphenated form returned no record');
        assert(
          result.nonprofit.ein === normalized,
          `hyphenated input resolved to ${result.nonprofit.ein}, expected ${normalized}`,
        );

        // The hyphen and the whitespace are normalized before the URL is built.
        const url = runner.requests.slice(before).at(-1)?.url ?? '';

        assert(url.endsWith(`/${normalized}`), `the request URL did not carry the normalized EIN: ${url}`);
        assert(!url.includes(hyphenated.trim()), 'the hyphenated form reached the URL');

        return { detail: `"${hyphenated.trim()}" and "${normalized}" address the same record` };
      },
    },

    {
      covers: ['ex-16'],
      name: 'not found',
      cost: 1,
      async body(runner) {
        const before = runner.requestsSent;

        try {
          const result = await runner.client.nonprofits.check(MISSING_EIN);

          runner.observeCycleCount(result.checkCount);

          if (result.nonprofit) {
            return {
              status: 'warn',
              detail: `${MISSING_EIN} unexpectedly has a record — MISSING_EIN needs an unused one`,
            };
          }

          runner.note('not found', 'a missing EIN returned HTTP 200 with a null record, not 404');

          return { status: 'warn', detail: `HTTP ${result.status} with data: null, not a 404` };
        } catch (error) {
          if (error instanceof PactmanNotFoundError) {
            assert(error.status === 404, `expected status 404, got ${error.status}`);
            assert(error.origin === 'api', `expected origin "api", got ${error.origin}`);
            assert(
              error instanceof PactmanApiError,
              'PactmanNotFoundError is not catchable as PactmanApiError',
            );

            // A 404 cannot become a record by asking again (ex-23).
            assert(
              runner.requestsSent - before === 1,
              `a 404 was retried: ${runner.requestsSent - before} requests`,
            );

            // Diagnostics must be safe to log verbatim.
            const serialized = JSON.stringify(error) + String(error.stack);

            assert(!serialized.includes(apiKey), 'the API key appeared in error diagnostics');

            return {
              detail:
                `HTTP 404 → PactmanNotFoundError · apiCode ${error.apiCode} · ` +
                `${error.apiErrors.length} detail(s) · not retried`,
            };
          }

          if (error instanceof PactmanApiError) {
            runner.note('not found', `a missing EIN produced HTTP ${error.status}, not 404`);

            return { status: 'warn', detail: `HTTP ${error.status} (${error.constructor.name})` };
          }

          throw error;
        }
      },
    },
  ];
}

// --- checks: the sources (ex-06..ex-14) -------------------------------------

function sourceChecks() {
  return [
    sourceProjection({
      covers: ['ex-07'],
      name: 'Publication 78 projection',
      get: getPub78,
      mapping: {
        verified: 'pub78_verified',
        organization_name: 'pub78_organization_name',
        ein: 'pub78_ein',
        city: 'pub78_city',
        state: 'pub78_state',
        indicator: 'pub78_indicator',
        church_message: 'pub78_church_message',
        source_org_type_1: 'pub78_source_org_type_1',
        source_org_type_2: 'pub78_source_org_type_2',
        source_org_type_3: 'pub78_source_org_type_3',
        organization_types: 'organization_types',
        most_recent: 'most_recent_pub78',
      },
      describe(pub78) {
        const types = Array.isArray(pub78.organization_types) ? pub78.organization_types : [];
        const limitation = types[0]?.deductibility_limitation;

        return (
          `verified: ${pub78.verified ?? 'not reported'} · ` +
          `${types.length} deductibility entr${types.length === 1 ? 'y' : 'ies'}` +
          (limitation ? ` · ${truncate(limitation, 24)}` : '')
        );
      },
    }),

    sourceProjection({
      covers: ['ex-06'],
      name: 'BMF projection',
      get: getBmf,
      mapping: {
        status: 'bmf_status',
        organization_name: 'bmf_organization_name',
        ein: 'bmf_ein',
        city: 'bmf_city',
        state: 'bmf_state',
        street_address: 'bmf_street_address',
        church_message: 'bmf_church_message',
        subsection: 'bmf_subsection',
        subsection_description: 'subsection_description',
        foundation_code: 'foundation_code',
        foundation_code_description: 'foundation_code_description',
        foundation_type_code: 'foundation_type_code',
        foundation_type_description: 'foundation_type_description',
        foundation_509a_status: 'foundation_509a_status',
        ruling_month: 'ruling_month',
        ruling_year: 'ruling_year',
        group_exemption: 'group_exemption',
        exempt_status_code: 'exempt_status_code',
        filing_req_code: 'filing_req_code',
        pf_filing_req_cd: 'bmf_source_pf_filing_req_cd',
        deductability_text: 'bmf_deductability_text',
        most_recent: 'most_recent_bmf',
      },
      describe(bmf) {
        return (
          `status: ${bmf.status ?? 'not reported'} · ` +
          `subsection ${bmf.subsection ?? '—'} · ` +
          `${truncate(bmf.subsection_description ?? 'no description', 30)}`
        );
      },
    }),

    sourceProjection({
      covers: ['ex-08', 'ex-09'],
      name: 'revocation (AROE) projection',
      get: getAroe,
      // Most organizations were never revoked, so an absent source is the
      // ordinary case here rather than something to flag.
      absentStatus: 'pass',
      mapping: {
        revocation_code: 'revocation_code',
        revocation_date: 'revocation_date',
        reinstatement_date: 'reinstatement_date',
        list_published_date: 'aroe_list_published_date',
      },
      describe(aroe) {
        if (!aroe.revocation_date && !aroe.revocation_code) {
          return 'no revocation on this record';
        }

        const revoked = parseApiDate(aroe.revocation_date);
        const reinstated = parseApiDate(aroe.reinstatement_date);
        const gap =
          revoked !== null && reinstated !== null
            ? ` · ${Math.round((reinstated - revoked) / 86_400_000)}d gap`
            : '';

        return `revoked ${aroe.revocation_date ?? '?'} (${aroe.revocation_code ?? 'no code'})${gap}`;
      },
    }),

    sourceProjection({
      covers: ['ex-10'],
      name: 'OFAC projection',
      get: getOfac,
      mapping: {
        status: 'ofac_status',
        list_published_date: 'ofac_list_published_date',
      },
      describe(ofac) {
        // The API reports a sentence. If it ever becomes a boolean, a caller who
        // was told to read prose needs to hear about it.
        return `"${truncate(ofac.status ?? 'null', 44)}" (${typeof ofac.status})`;
      },
    }),

    fromRecord(['ex-10'], 'OFAC stays four-valued', (nonprofit, runner) => {
      const ofac = getOfac(nonprofit);
      const state =
        ofac === null ? 'unavailable' : ofac.status === null ? 'null' : typeof ofac.status;

      assert(
        state !== 'boolean',
        'ofac_status came back as a boolean — screening logic that reads prose will silently break',
      );

      if (state === 'unavailable') {
        runner.note('OFAC stays four-valued', 'nothing was screened against the SDN list for this record');
      }

      return {
        status: state === 'unavailable' ? 'warn' : 'pass',
        detail: `screened → ${state === 'string' ? 'a sentence' : state} · no boolean derived from it`,
      };
    }),

    fromRecord(['ex-11'], 'cross-source conflict', (nonprofit, runner) => {
      const conflict = nonprofit.irs_bmf_pub78_conflict;

      assert(
        conflict === undefined || conflict === null || typeof conflict === 'boolean',
        `irs_bmf_pub78_conflict came back as ${typeof conflict}`,
      );

      if (conflict === true) {
        runner.note(
          'cross-source conflict',
          `BMF and Publication 78 disagree: bmf_status ${nonprofit.bmf_status}, ` +
            `pub78_verified ${nonprofit.pub78_verified} — both preserved, neither resolved`,
        );

        return { detail: 'conflict reported and both sources preserved' };
      }

      return {
        detail:
          conflict === false
            ? 'no conflict between BMF and Publication 78'
            : 'the API did not report a conflict flag for this record',
      };
    }),

    fromRecord(['ex-12'], 'foundation classification', (nonprofit, runner) => {
      const pairs = [
        ['bmf_subsection', 'subsection_description'],
        ['foundation_code', 'foundation_code_description'],
        ['foundation_type_code', 'foundation_type_description'],
      ];

      // A description is the source's own label. One arriving without its code
      // would mean the label came from somewhere else (ex-12).
      for (const [code, description] of pairs) {
        if (returned(nonprofit, description) && nonprofit[description] !== null) {
          assert(
            returned(nonprofit, code),
            `${description} was returned without ${code} — the label has no source value behind it`,
          );
        }
      }

      const described = pairs.filter(([, description]) => Boolean(nonprofit[description])).length;

      if (described < pairs.length) {
        runner.note(
          'foundation classification',
          `${pairs.length - described} classification code(s) arrived without a description`,
        );
      }

      return {
        detail:
          `509(a): ${nonprofit.foundation_509a_status ?? '—'} · ` +
          `${truncate(nonprofit.foundation_code_description ?? 'no foundation description', 34)}`,
        data: { described, of: pairs.length },
      };
    }),

    fromRecord(['ex-13'], 'filing and exemption metadata', (nonprofit, runner) => {
      const codes = [
        'filing_req_code',
        'exempt_status_code',
        'group_exemption',
        'bmf_source_pf_filing_req_cd',
        'ruling_month',
        'ruling_year',
      ];

      // Codes are preserved exactly as sent — never coerced, never re-labelled.
      for (const code of codes) {
        const value = nonprofit[code];

        assert(
          value === undefined || value === null || typeof value === 'string' || typeof value === 'number',
          `${code} came back as ${typeof value}`,
        );
      }

      const year = Number(nonprofit.ruling_year);
      const month = Number(nonprofit.ruling_month);

      if (nonprofit.ruling_year != null && !(year >= 1900 && year <= new Date().getFullYear())) {
        runner.note('filing and exemption metadata', `ruling_year is "${nonprofit.ruling_year}"`);
      }

      if (nonprofit.ruling_month != null && !(month >= 1 && month <= 12)) {
        runner.note('filing and exemption metadata', `ruling_month is "${nonprofit.ruling_month}"`);
      }

      const returnedCodes = codes.filter(code => Boolean(nonprofit[code]));

      return {
        detail:
          `${returnedCodes.length}/${codes.length} codes returned verbatim · ` +
          `ruling ${nonprofit.ruling_month ?? '?'}/${nonprofit.ruling_year ?? '?'}`,
        data: Object.fromEntries(codes.map(code => [code, nonprofit[code] ?? null])),
      };
    }),

    fromRecord(['ex-14'], 'data freshness', (nonprofit, runner) => {
      const dateFields = [
        'report_date',
        'organization_info_last_modified',
        'most_recent_bmf',
        'most_recent_pub78',
        'ofac_list_published_date',
        'aroe_list_published_date',
        'revocation_date',
        'reinstatement_date',
      ];

      const now = Date.now();
      const ages = [];
      const unparsable = [];
      const future = [];

      for (const field of dateFields) {
        const value = nonprofit[field];

        if (value === undefined || value === null || value === '') {
          continue;
        }

        const timestamp = parseApiDate(value);

        if (timestamp === null) {
          unparsable.push(`${field}="${value}"`);
          continue;
        }

        if (timestamp > now + 86_400_000) {
          future.push(`${field}=${value}`);
        }

        ages.push({ field, days: ageInDays(timestamp, now) });
      }

      if (unparsable.length > 0) {
        runner.note('data freshness', `dates that do not parse as dates: ${unparsable.join(', ')}`);
      }

      if (future.length > 0) {
        runner.note('data freshness', `dates in the future: ${future.join(', ')}`);
      }

      if (ages.length === 0) {
        runner.note('data freshness', 'no source date was returned — the record carries no freshness signal');

        return { status: 'warn', detail: 'no dates on this record' };
      }

      const oldest = ages.reduce((worst, entry) => (entry.days > worst.days ? entry : worst));

      return {
        status: unparsable.length > 0 || future.length > 0 ? 'warn' : 'pass',
        detail: `${ages.length}/${dateFields.length} dates · oldest ${oldest.field} at ${oldest.days}d`,
        data: { ages },
      };
    }),
  ];
}

// --- checks: forward compatibility (ex-25) ----------------------------------

function forwardCompatibilityChecks() {
  return [
    {
      covers: ['ex-25'],
      name: 'raw envelope is unmodified',
      cost: 0,
      body(runner) {
        const result = runner.singleResult;

        if (!result) {
          return { status: 'skip', detail: 'the single check did not return a record' };
        }

        const data = result.raw.data;
        const expected = Array.isArray(data) ? data[0] : data;
        const numeric = value => (typeof value === 'number' ? value : null);

        assert(
          Object.is(result.nonprofit, expected),
          'result.nonprofit is a copy of the body, not the body itself',
        );
        assert(
          result.checkCount === numeric(result.raw.nonprofit_check_count),
          'checkCount does not match the envelope it was read from',
        );
        assert(
          result.timeTakenMs === numeric(result.raw.timeTaken),
          'timeTakenMs does not match the envelope it was read from',
        );

        return {
          detail: `raw carries ${Object.keys(result.raw).length} envelope keys, none rewritten`,
        };
      },
    },

    fromRecord(['ex-25'], 'no wire field is dropped', (nonprofit, runner) => {
      const raw = runner.singleResult.raw;
      const data = Array.isArray(raw.data) ? raw.data[0] : raw.data;
      const wireFields = Object.keys(data);

      // Whatever the API adds, the installed SDK still hands it over.
      for (const field of wireFields) {
        assert(field in nonprofit, `the wire field "${field}" is not readable on the model`);
        assert(
          Object.is(nonprofit[field], data[field]),
          `the value of "${field}" was altered between the wire and the model`,
        );
      }

      const unknown = wireFields.filter(field => !KNOWN_NONPROFIT_FIELDS.has(field));

      assert(
        nonprofit.a_field_this_api_has_never_sent === undefined,
        'index access invented a value for a field that was never returned',
      );

      return {
        detail:
          `${wireFields.length} wire fields readable · ` +
          (unknown.length > 0
            ? `${unknown.length} newer than this SDK and still reachable`
            : 'none newer than this SDK on this record'),
        data: { unknown },
      };
    }),
  ];
}

// --- checks: bulk (ex-17..ex-21) --------------------------------------------

function bulkChecks(eins) {
  const bulkEins = eins.slice(0, Math.min(eins.length, 3));
  const duplicateProbe = eins.length >= 2 ? [eins[1], eins[0], eins[1]] : null;
  const checks = [];

  checks.push({
    covers: ['ex-19', 'bulk'],
    name: 'bulk partial success',
    cost: bulkEins.length + 1,
    async body(runner) {
      const submitted = [...bulkEins, MISSING_EIN];
      let result;

      try {
        result = await runner.client.nonprofits.checkBulk(submitted);
      } catch (error) {
        if (!isFreeTierRestriction(error)) {
          throw error;
        }

        // The batch was refused for containing an EIN outside the key's
        // allowlist, so nothing was looked up and partial success was never
        // exercised. Record the key class for the checks that depend on it.
        runner.freeTierKey = true;
        runner.note(
          'bulk partial success',
          `this key restricts bulk requests to a fixed set of EINs, so a batch containing ${MISSING_EIN} was refused whole — rerun with a key that has open bulk access to verify partial success`,
        );

        return {
          status: 'skip',
          detail: 'the key restricts bulk EINs to an allowlist — partial success is unreachable',
        };
      }

      runner.observeCycleCount(result.checkCount);
      runner.captureBulk(result, submitted);

      assert(
        result.status === 200,
        `a batch with matches and misses returned HTTP ${result.status}, expected 200`,
      );
      assert(result.organizations.length > 0, 'no organizations were returned');

      if (!result.notFoundEins.includes(normalizeEin(MISSING_EIN))) {
        runner.note(
          'bulk partial success',
          `the missing EIN was not reported in errors[].eins; notFoundEins = ${JSON.stringify(result.notFoundEins)}`,
        );
      }

      // Every input must map to a matched record or a reported failure.
      const matched = new Set(result.organizations.map(org => org.ein));
      const missing = new Set(result.notFoundEins);
      const unaccounted = submitted
        .map(value => normalizeEin(value))
        .filter(value => !matched.has(value) && !missing.has(value));

      if (unaccounted.length > 0) {
        runner.note(
          'bulk partial success',
          `inputs with neither a record nor an error: ${unaccounted.join(', ')}`,
        );
      }

      return {
        status: unaccounted.length > 0 ? 'warn' : 'pass',
        detail: `${result.organizations.length} matched · ${result.notFoundEins.length} missing · ${result.errors.length} error entries`,
        data: { notFoundEins: result.notFoundEins },
      };
    },
  });

  if (duplicateProbe) {
    checks.push({
      covers: ['ex-18'],
      name: 'bulk order and duplicates',
      cost: duplicateProbe.length,
      async body(runner) {
        const before = runner.requests.length;
        const result = await runner.client.nonprofits.checkBulk(duplicateProbe);

        runner.observeCycleCount(result.checkCount);
        runner.captureBulk(result, duplicateProbe);

        const requested = duplicateProbe.map(value => normalizeEin(value));
        const returnedEins = result.organizations.map(org => org.ein);
        const uniqueRequested = [...new Set(requested)];

        // The SDK sends what it was given, duplicates and order included.
        const sentBody = runner.requests.slice(before).at(-1)?.body;

        if (typeof sentBody === 'string') {
          assert(
            JSON.stringify(requested) === sentBody,
            `the request body was ${sentBody}, not the EINs as supplied`,
          );
        }

        const positional =
          returnedEins.length === requested.length && returnedEins.every((v, i) => v === requested[i]);
        const dedupedOrder =
          returnedEins.length === uniqueRequested.length &&
          returnedEins.every((v, i) => v === uniqueRequested[i]);
        const collapsed = returnedEins.length === new Set(returnedEins).size;

        // These are observations about the deployment, recorded either way — the
        // README's claims are what they check.
        runner.note(
          'bulk order and duplicates',
          `sent [${requested.join(', ')}] → received [${returnedEins.join(', ')}]`,
        );
        runner.note(
          'bulk order and duplicates',
          positional
            ? 'response order matched request order on this call — the API does not guarantee it, so keep indexing by EIN'
            : 'response order did not match request order, as documented — index by EIN',
        );

        assert(collapsed, 'a duplicated EIN was returned more than once, which contradicts set matching');

        return {
          detail: `duplicate collapsed to one record · request-order match: ${positional} · deduped-order match: ${dedupedOrder}`,
          data: { requested, returned: returnedEins, positional },
        };
      },
    });
  }

  checks.push({
    covers: ['ex-17'],
    name: 'bulk and single agree',
    cost: 0,
    body(runner) {
      const single = runner.singleResult?.nonprofit;
      const bulk = runner.bulkResult;

      if (!single || !bulk) {
        return { status: 'skip', detail: 'both a single and a bulk result are needed' };
      }

      const twin = bulk.organizations.find(org => org.ein === single.ein);

      if (!twin) {
        return { status: 'skip', detail: `${single.ein} was not among the bulk results` };
      }

      assert(
        twin.organization_name === single.organization_name,
        `the two endpoints disagree about the name: "${single.organization_name}" vs "${twin.organization_name}"`,
      );

      // A record that is thinner in bulk is a real trap for anyone who screens in
      // bulk and reads fields the single endpoint taught them to expect.
      const onlySingle = Object.keys(single).filter(field => !(field in twin));
      const onlyBulk = Object.keys(twin).filter(field => !(field in single));

      if (onlySingle.length > 0) {
        runner.note(
          'bulk and single agree',
          `the bulk record omits: ${onlySingle.join(', ')} — do not assume bulk records are complete`,
        );
      }

      if (onlyBulk.length > 0) {
        runner.note('bulk and single agree', `only the bulk record carries: ${onlyBulk.join(', ')}`);
      }

      return {
        status: onlySingle.length > 0 || onlyBulk.length > 0 ? 'warn' : 'pass',
        detail:
          onlySingle.length + onlyBulk.length === 0
            ? `identical field sets for ${single.ein} on both endpoints`
            : `${onlySingle.length} field(s) only in single · ${onlyBulk.length} only in bulk`,
        data: { onlySingle, onlyBulk },
      };
    },
  });

  checks.push({
    covers: ['ex-21'],
    name: 'bulk usage accounting',
    cost: 0,
    body(runner) {
      const single = runner.singleResult;
      const bulk = runner.bulkResult;

      if (!single || !bulk) {
        return { status: 'skip', detail: 'both a single and a bulk result are needed' };
      }

      if (single.checkCount === null || bulk.checkCount === null) {
        return { status: 'skip', detail: 'the API did not report nonprofit_check_count' };
      }

      assert(
        bulk.checkCount >= single.checkCount,
        `the counter fell from ${single.checkCount} to ${bulk.checkCount} between a single and a bulk call`,
      );

      const batchSize = runner.bulkSubmitted?.length ?? 0;

      // If it ever equals the batch size, someone is about to reconstruct usage
      // from their own input and be wrong (ex-18, ex-21).
      if (bulk.checkCount === batchSize) {
        runner.note(
          'bulk usage accounting',
          `the bulk response reported ${bulk.checkCount}, exactly the batch size — verify it is still a cycle total`,
        );

        return { status: 'warn', detail: `checkCount ${bulk.checkCount} equals the ${batchSize}-EIN batch size` };
      }

      return {
        detail: `${single.checkCount} → ${bulk.checkCount} across a ${batchSize}-EIN batch · a cycle total, not a batch size`,
        data: { single: single.checkCount, bulk: bulk.checkCount, batchSize },
      };
    },
  });

  return checks;
}

// --- checks: the raw response contract --------------------------------------

/**
 * Four checks that hold the raw JSON this run received against a recorded
 * baseline: the schema and the types of the single-check response, and the same
 * two for bulk.
 *
 * Everything else in this file asserts what the SDK does with a response. These
 * assert that the response itself has not moved — a field the API stopped
 * sending, one it started sending, one that changed from a boolean to a string
 * or from `M/D/YYYY h:mm:ss AM` to ISO. None of it is knowable from the SDK's
 * own types, which are permissive by design so a server-side change cannot break
 * deserialization; this is where such a change is meant to become visible.
 *
 * Free. Both responses were already fetched and paid for by the checks above.
 *
 * The first run against a deployment has nothing to compare to, so it records
 * what it saw and says so; every run after that is a comparison. A fifth entry
 * writes the file when there is something new to write, and stands down when
 * there is not.
 *
 * The baseline holds shapes only — path, type and value format, never a value —
 * so it is safe to commit and a failure is safe to print. See `contract.mjs`.
 */
function contractChecks() {
  const baselinePath = fileURLToPath(new URL('./contract-baseline.json', import.meta.url));

  /** Read once, on the first check that needs it. */
  let baseline;
  let baselineError = null;

  function loadBaseline() {
    if (baseline === undefined) {
      baseline = null;

      if (existsSync(baselinePath)) {
        try {
          baseline = JSON.parse(readFileSync(baselinePath, 'utf8'));
        } catch (error) {
          baselineError = `${basename(baselinePath)} is not readable JSON: ${error.message}`;
        }
      }
    }

    return baseline;
  }

  /** Signatures this run observed, by endpoint. Built once, read by both checks. */
  const observed = {};

  function observe(runner, kind) {
    if (observed[kind] === undefined) {
      const source =
        kind === 'single'
          ? {
              raw: runner.singleResult?.raw,
              subject: { ein: runner.singleResult?.nonprofit?.ein ?? null },
              missing: 'the single check did not return a response',
            }
          : {
              raw: runner.bulkResult?.raw,
              subject: { eins: (runner.bulkSubmitted ?? []).map(value => normalizeEin(value)) },
              missing: runner.freeTierKey
                ? 'this key restricts bulk EINs to an allowlist, so no bulk response was returned'
                : 'the bulk check did not return a response',
            };

      observed[kind] =
        source.raw === undefined
          ? { missing: source.missing }
          : { subject: source.subject, signature: signatureOf(source.raw) };
    }

    return observed[kind];
  }

  /**
   * A baseline recorded against a different organization, or a different batch,
   * describes a different record. Comparing the two would report data variation
   * as API drift, so the checks stand down instead.
   */
  function subjectMismatch(recorded, subject) {
    if (subject.ein && recorded.ein && recorded.ein !== subject.ein) {
      return `the baseline was recorded for EIN ${recorded.ein}, this run used ${subject.ein}`;
    }

    if (subject.eins && recorded.eins && recorded.eins.join(',') !== subject.eins.join(',')) {
      return (
        `the baseline was recorded for EINs ${recorded.eins.join(', ')}, ` +
        `this run used ${subject.eins.join(', ')}`
      );
    }

    return null;
  }

  /** Endpoints whose signature has to be written out at the end of the run. */
  const pending = new Set();

  let announcedTarget = false;

  /**
   * Both checks on an endpoint do the same work along different axes: signature
   * of what arrived, held against the recorded one by `diff`.
   *
   * With nothing recorded for this endpoint yet, there is nothing to hold it
   * against, so this run becomes the baseline. That is the whole first-run
   * ceremony: run it, and from the next run on the comparison is live. Deleting
   * the file is how a recording is redone, and deleting it is deliberate work —
   * re-recording discards the evidence a comparison would have given.
   */
  function against({ kind, name, diff, describe }) {
    return {
      covers: ['contract'],
      name,
      cost: 0,
      body(runner) {
        const current = observe(runner, kind);

        if (current.missing) {
          return { status: 'skip', detail: current.missing };
        }

        const paths = Object.keys(current.signature).length;
        const stored = loadBaseline();

        if (baselineError) {
          throw new Error(baselineError);
        }

        const recorded = stored?.[kind]?.signature ? stored[kind] : null;

        if (!recorded) {
          pending.add(kind);

          return {
            detail: `${paths} paths recorded — the next run checks against them`,
            data: { paths, recorded: true },
          };
        }

        const mismatch = subjectMismatch(recorded, current.subject);

        if (mismatch) {
          return { status: 'skip', detail: `${mismatch} — the two describe different records` };
        }

        const recordedBaseUrl = recorded.baseUrl ?? stored.baseUrl;

        if (!announcedTarget && recordedBaseUrl && recordedBaseUrl !== runner.client.baseUrl) {
          announcedTarget = true;
          runner.note(
            name,
            `the baseline was recorded against ${recordedBaseUrl}; this run targeted ${runner.client.baseUrl}, ` +
              'so a difference may be between deployments rather than over time',
          );
        }

        const result = diff(recorded.signature, current.signature);

        assert(
          result.total === 0,
          `the live ${kind} response no longer matches ${basename(baselinePath)} — ` +
            `${summarizeChanges(result.changes)}\n${formatChanges(result.changes)}\n` +
            `      delete ${basename(baselinePath)} and re-run to re-record, ` +
            'once the change is understood and intended',
        );

        return {
          detail: `${describe(paths)} · ${baselineAge(recorded, stored)}`,
          data: { paths, recordedAt: recorded.recordedAt ?? stored.recordedAt ?? null },
        };
      },
    };
  }

  const checks = [
    against({
      kind: 'single',
      name: 'single response schema',
      diff: schemaDiff,
      describe: paths => `${paths} paths, none added or removed`,
    }),
    against({
      kind: 'single',
      name: 'single response types',
      diff: typeDiff,
      describe: paths => `${paths} paths carry the recorded types and value formats`,
    }),
    against({
      kind: 'bulk',
      name: 'bulk response schema',
      diff: schemaDiff,
      describe: paths => `${paths} paths, none added or removed`,
    }),
    against({
      kind: 'bulk',
      name: 'bulk response types',
      diff: typeDiff,
      describe: paths => `${paths} paths carry the recorded types and value formats`,
    }),
  ];

  checks.push({
    covers: ['contract'],
    name: 'baseline',
    cost: 0,
    body(runner) {
      const previous = loadBaseline() ?? {};
      const written = ['single', 'bulk'].filter(
        kind => pending.has(kind) && observed[kind]?.signature,
      );

      if (written.length === 0) {
        return {
          status: 'skip',
          detail: `${basename(baselinePath)} already covers what this run observed`,
        };
      }

      // Only what this run recorded is rewritten. An endpoint that was checked,
      // or that this run never reached, keeps the shape already on file — a
      // failed comparison must not quietly become the new baseline.
      const recordFor = kind =>
        written.includes(kind)
          ? {
              recordedAt: new Date().toISOString(),
              baseUrl: runner.client.baseUrl,
              sdkVersion: VERSION,
              ...observed[kind].subject,
              signature: observed[kind].signature,
            }
          : (previous[kind] ?? null);

      const kept = ['single', 'bulk'].filter(
        kind => !written.includes(kind) && previous[kind]?.signature,
      );

      writeFileSync(
        baselinePath,
        `${JSON.stringify(
          {
            note:
              'Shape of the live API responses: path, JSON type and value format, no values. ' +
              'Recorded on first run; delete this file and re-run to re-record.',
            single: recordFor('single'),
            bulk: recordFor('bulk'),
          },
          null,
          2,
        )}\n`,
      );

      return {
        detail:
          `${written.join(' and ')} written to ${basename(baselinePath)} — commit it` +
          (kept.length > 0 ? ` · ${kept.join(' and ')} left as recorded` : ''),
        data: { written, kept },
      };
    },
  });

  return checks;
}

/** How old the recorded baseline is, for the detail line. */
function baselineAge(recorded, stored) {
  const recordedAt = Date.parse(recorded.recordedAt ?? stored.recordedAt ?? '');

  return Number.isNaN(recordedAt)
    ? 'baseline of unknown age'
    : `baseline ${ageInDays(recordedAt)}d old`;
}

// --- checks: rechecking the same record (ex-28..ex-30) ----------------------

function recheckChecks(ein) {
  return [
    {
      covers: ['ex-29', 'ex-28', 'ex-30'],
      name: 'a repeat check is stable',
      cost: 1,
      async body(runner) {
        const first = runner.singleResult;

        if (!first?.nonprofit) {
          return { status: 'skip', detail: 'the single check did not return a record' };
        }

        const second = await runner.client.nonprofits.check(ein);

        runner.observeCycleCount(second.checkCount);

        assert(second.nonprofit !== null, 'the same EIN returned no record on the second call');
        assert(
          second.nonprofit.ein === first.nonprofit.ein,
          'the two calls returned different EINs for the same request',
        );

        // A scheduled re-verification compares fields between runs. Fields that
        // appear and disappear between two calls seconds apart would make every
        // diff meaningless (ex-29, ex-30).
        const appeared = Object.keys(second.nonprofit).filter(field => !(field in first.nonprofit));
        const vanished = Object.keys(first.nonprofit).filter(field => !(field in second.nonprofit));
        const changed = Object.keys(first.nonprofit).filter(
          field =>
            field in second.nonprofit &&
            JSON.stringify(first.nonprofit[field]) !== JSON.stringify(second.nonprofit[field]),
        );

        for (const [label, fields] of [
          ['appeared', appeared],
          ['vanished', vanished],
          ['changed', changed],
        ]) {
          if (fields.length > 0) {
            runner.note('a repeat check is stable', `fields that ${label} between two calls: ${fields.join(', ')}`);
          }
        }

        const distinctIds =
          first.requestId !== null && second.requestId !== null && first.requestId !== second.requestId;

        if (first.requestId !== null && !distinctIds) {
          runner.note(
            'a repeat check is stable',
            'both calls reported the same request id — an audit trail cannot tell them apart',
          );
        }

        const drifted = appeared.length + vanished.length + changed.length;

        return {
          status: drifted > 0 ? 'warn' : 'pass',
          detail:
            (drifted === 0
              ? `${Object.keys(second.nonprofit).length} fields identical across two calls`
              : `${drifted} field(s) differed between two calls seconds apart`) +
            ` · request ids ${distinctIds ? 'distinct' : 'not distinguishable'}`,
          data: { appeared, vanished, changed },
        };
      },
    },

    {
      covers: ['ex-21'],
      name: 'check count is cumulative',
      cost: 0,
      body(runner) {
        const { cycleCountStart: start, cycleCountEnd: end } = runner;

        if (start === null || end === null) {
          return { status: 'skip', detail: 'the API did not report nonprofit_check_count' };
        }

        assert(end >= start, `the counter went backwards: ${start} → ${end}`);

        if (end === start) {
          // A free key reports the size of each request rather than a running
          // cycle total, so a flat counter is the documented behaviour for that
          // key class and proves nothing about the cumulative contract.
          if (runner.freeTierKey) {
            runner.note(
              'check count is cumulative',
              `the counter reported the size of each request and never accumulated (${start} → ${end}) — expected for a key with allowlisted EINs`,
            );

            return {
              status: 'skip',
              detail: 'this key reports a per-request count — a cumulative total needs a metered key',
            };
          }

          runner.note(
            'check count is cumulative',
            `the counter did not move across ${runner.checksSpent} billable checks (${start} → ${end})`,
          );

          return { status: 'warn', detail: `unchanged at ${start} — expected a cumulative total` };
        }

        return {
          detail: `${start} → ${end} (+${end - start}) across the run · a running billing-cycle total, not a request size`,
          data: { start, end },
        };
      },
    },
  ];
}

// --- checks: what actually went on the wire (ex-01, ex-17, ex-20) -----------

function wireChecks(apiKey) {
  const singlePattern = new RegExp(
    `${SINGLE_CHECK_PATH.replace(/[.*+?^${}()|[\]\\]/g, '\\$&').replace('\\{ein\\}', '\\d{9}')}$`,
  );

  return [
    {
      covers: ['ex-17', 'ex-03'],
      name: 'documented endpoints and methods',
      cost: 0,
      body(runner) {
        if (runner.requests.length === 0) {
          return { status: 'skip', detail: 'no requests were sent' };
        }

        let singles = 0;
        let bulks = 0;

        for (const request of runner.requests) {
          const url = new URL(request.url);

          assert(url.search === '', `a request carried a query string: ${url.search}`);
          assert(
            request.url.startsWith(runner.client.baseUrl),
            `a request went somewhere other than the configured host: ${request.url}`,
          );

          if (request.method === 'POST') {
            assert(url.pathname === BULK_CHECK_PATH, `POST went to ${url.pathname}, not BULK_CHECK_PATH`);
            assert(request.contentType === 'application/json', 'the bulk request was not JSON');

            const body = JSON.parse(request.body ?? 'null');

            assert(Array.isArray(body), 'the bulk body was not a JSON array of EINs');
            assert(
              body.every(value => /^\d{9}$/.test(value)),
              'the bulk body carried EINs that were not normalized',
            );

            bulks += 1;
          } else {
            assert(request.method === 'GET', `unexpected method ${request.method}`);
            assert(singlePattern.test(url.pathname), `GET went to ${url.pathname}, not SINGLE_CHECK_PATH`);
            assert(request.body === null, 'a GET carried a body');

            singles += 1;
          }
        }

        return {
          detail: `${singles} GET on SINGLE_CHECK_PATH · ${bulks} POST on BULK_CHECK_PATH · no query strings`,
          data: { singles, bulks },
        };
      },
    },

    {
      covers: ['ex-01'],
      name: 'credentials stay off the wire',
      cost: 0,
      body(runner) {
        if (runner.requests.length === 0) {
          return { status: 'skip', detail: 'no requests were sent' };
        }

        const userAgentPrefix = 'pactmandev-nonprofit-check-plus/';

        for (const request of runner.requests) {
          assert(!request.urlCarriesKey, `the API key appeared in a request URL: ${request.url}`);
          assert(request.authCarriesKey, 'a request went out without the key in its Authorization header');
          assert(
            request.authScheme === 'Bearer',
            `the Authorization header used the "${request.authScheme}" scheme`,
          );
          assert(request.accept === 'application/json', `Accept was "${request.accept}"`);
          assert(
            request.userAgent?.startsWith(userAgentPrefix) && request.userAgent.includes(VERSION),
            `the User-Agent does not identify this SDK version: ${request.userAgent}`,
          );
        }

        // Belt and braces: the recorded log itself must be safe to print.
        assert(
          !JSON.stringify(runner.requests).includes(apiKey),
          'the recorded request log contains the API key',
        );

        return {
          detail: `${runner.requests.length} requests · key in Authorization only · UA ${userAgentPrefix}${VERSION}`,
        };
      },
    },
  ];
}

// --- checks: the disruptive probes (ex-22, ex-24) ---------------------------

/**
 * The two probes that misbehave on purpose: one starves a request of time, the
 * other bursts until the server pushes back.
 *
 * They used to be opt-in, which meant the sign-off run routinely proved
 * everything except the two paths a caller meets on their worst day. They are
 * part of the plan now. The burst is bounded and stops the moment a 429 arrives.
 */
function probeChecks(ein) {
  return [
    {
      covers: ['ex-24'],
      name: 'timeout and cancellation',
      cost: 2,
      async body(runner) {
        let timedOut = false;
        let cancelled = false;

        // Short enough that the response cannot arrive, long enough that the
        // connection has been established — otherwise the socket fails first and
        // the SDK correctly reports a network error rather than a timeout.
        const deadlineMs = Math.max(2, Math.round((runner.observedRoundTripMs ?? 100) * 0.3));

        try {
          await runner.client.nonprofits.check(ein, { timeoutMs: deadlineMs, retry: false });
        } catch (error) {
          timedOut = error instanceof PactmanTimeoutError;

          if (timedOut) {
            assert(
              error.timeoutMs === deadlineMs,
              `error.timeoutMs was ${error.timeoutMs}, expected ${deadlineMs}`,
            );
            assert(error.origin === 'local', `a timeout reported origin "${error.origin}"`);
          } else if (!(error instanceof PactmanNetworkError)) {
            throw error;
          }
        }

        const controller = new AbortController();
        controller.abort(new Error('smoke test cancellation'));

        try {
          await runner.client.nonprofits.check(ein, { signal: controller.signal });
        } catch (error) {
          cancelled = error instanceof PactmanNetworkError && !(error instanceof PactmanTimeoutError);
        }

        assert(cancelled, 'an aborted request did not raise PactmanNetworkError');

        if (!timedOut) {
          runner.note(
            'timeout and cancellation',
            `a ${deadlineMs}ms deadline produced a network error rather than a timeout — ` +
              'expected when the round trip is very short, as on a local host',
          );
        }

        return {
          status: timedOut ? 'pass' : 'warn',
          detail:
            `${deadlineMs}ms deadline → ${timedOut ? 'PactmanTimeoutError' : 'a network error'}` +
            ' · abort → PactmanNetworkError',
        };
      },
    },

    {
      covers: ['ex-22', 'error-handling'],
      name: 'rate limit',
      cost: RATE_LIMIT_ATTEMPTS,
      async body(runner) {
        for (let attempt = 1; attempt <= RATE_LIMIT_ATTEMPTS; attempt += 1) {
          try {
            const result = await runner.client.nonprofits.check(ein, { retry: false });

            runner.observeCycleCount(result.checkCount);
          } catch (error) {
            if (error instanceof PactmanRateLimitError) {
              assert(error.status === 429, `expected status 429, got ${error.status}`);

              return {
                detail:
                  `429 after ${attempt} request(s) → PactmanRateLimitError · ` +
                  `Retry-After ${error.retryAfterSeconds ?? 'not sent'}`,
                data: { attempt, retryAfterSeconds: error.retryAfterSeconds },
              };
            }

            throw error;
          }
        }

        return {
          status: 'warn',
          detail: `no 429 within ${RATE_LIMIT_ATTEMPTS} sequential requests — the limit was not reached`,
        };
      },
    },
  ];
}

/**
 * The plan: every check in this file, in the order their results depend on.
 *
 * The record-derived checks read what the single check fetched, the contract
 * checks read both responses, and the wire checks read the log every earlier
 * check wrote — so this order is not the order the report is read in, and the
 * report regroups it.
 *
 * Nothing here is conditional. Each entry declares its billable cost so the
 * total can be printed before the first request goes out.
 */
function buildPlan(apiKey, baseUrl) {
  return [
    ...clientChecks(apiKey),
    ...localValidationChecks(EIN, apiKey),
    ...authenticationChecks(EIN, baseUrl),
    ...singleCheckChecks(EIN, apiKey),
    ...sourceChecks(),
    ...forwardCompatibilityChecks(),
    ...bulkChecks(BULK_EINS),
    ...contractChecks(),
    ...recheckChecks(EIN),
    ...wireChecks(apiKey),
    ...probeChecks(EIN),
  ];
}

// --- the report -------------------------------------------------------------

/** Column the detail text starts in, so the results read as two columns. */
const NAME_WIDTH = 34;

/** A name in its column, never run together with the detail beside it. */
function column(name, width = NAME_WIDTH) {
  return name.length < width ? name.padEnd(width) : `${name} `;
}

/** The observations each check recorded, keyed by the check that recorded them. */
function findingsByCheck(findings) {
  const byCheck = new Map();

  for (const finding of findings) {
    byCheck.set(finding.check, [...(byCheck.get(finding.check) ?? []), finding.message]);
  }

  return byCheck;
}

/**
 * One heading per example file, and under it what this run has to say about
 * what that file claims.
 *
 * A check that covers more than one example is printed in full under the first
 * and referred to under the rest, so an example whose claim is proven somewhere
 * else says where instead of looking untested — and nothing is counted twice.
 */
function printReport(groups, findings) {
  const observations = findingsByCheck(findings);

  for (const group of groups) {
    say(`\n${group.id}  ${group.title}`);

    for (const result of group.primary) {
      say(
        `  ${STATUS[result.status]} ${column(result.name)}${result.detail}` +
          (result.cost > 0 ? `  [${result.cost} check(s)]` : ''),
      );

      for (const message of observations.get(result.name) ?? []) {
        say(`      · ${message}`);
      }
    }

    for (const { entry, under } of group.secondary) {
      say(`  ↳ ${STATUS[entry.status]} ${column(entry.name, NAME_WIDTH - 2)}checked under ${under}`);
    }

    if (group.primary.length === 0 && group.secondary.length === 0) {
      say('  – no check of its own — it composes examples checked above');
    }
  }
}

// --- main -------------------------------------------------------------------

const envFile = loadEnvFile();

// Before the key check, so `--help` and a bad EIN are answered without one.
const subjects = resolveSubjects(process.argv.slice(2), envFile);
const [EIN, BULK_EINS, MISSING_EIN] = subjects.map(subject => subject.value);

const apiKey = process.env[API_KEY_ENV];

if (!apiKey) {
  console.error(`No API key. Put ${API_KEY_ENV} in nodejs/.env, or export it, and run this again.`);
  process.exit(2);
}

secrets.add(apiKey);
secrets.add(INVALID_API_KEY);

const baseUrl = process.env.PACTMAN_BASE_URL ?? baseUrlForEnvironment(DEFAULT_ENVIRONMENT);
const examples = discoverExamples();
const plan = buildPlan(apiKey, baseUrl);
const plannedCost = plan.reduce((total, check) => total + check.cost, 0);
const freeChecks = plan.filter(check => check.cost === 0).length;

say(`Target        ${baseUrl}`);
say(`Key           from ${keySource(envFile)} (${apiKey.length} characters, never printed)`);
const ignoredSubjects = subjects.flatMap(subject => subject.ignored);

say(
  `Subjects      ${EIN} · bulk ${BULK_EINS.join(', ')} · no record ${MISSING_EIN}` +
    ` (from ${[...new Set(subjects.map(subject => subject.source))].join(', ')})`,
);

if (ignoredSubjects.length > 0) {
  say(`              ${ignoredSubjects.join(', ')} not used — the bulk probes read the first ${BULK_EINS.length}`);
}
say(`Plan          ${plan.length} checks across ${examples.length} example files, ${freeChecks} of them free`);
say(`Cost          ${plannedCost} billable API checks, charged to this key`);
say('');

const runner = new Runner(apiKey);

// Records every outbound request, so "nothing was sent" and "the key never left
// the Authorization header" can be asserted rather than assumed.
const recordingFetch = (input, init) => {
  runner.recordRequest(input, init);

  return globalThis.fetch(input, init);
};

runner.client = new PactmanClient({
  apiKey,
  baseUrl,
  timeoutMs: 20_000,
  retry: { maxRetries: 2 },
  fetch: recordingFetch,
});

const startedAt = Date.now();

/** Prints everything the run learned, however it ended, and stops. */
function finish(exitCode) {
  const counts = {
    total: runner.results.length,
    pass: runner.results.filter(result => result.status === 'pass').length,
    warn: runner.results.filter(result => result.status === 'warn').length,
    fail: runner.results.filter(result => result.status === 'fail').length,
    skip: runner.results.filter(result => result.status === 'skip').length,
  };

  const groups = groupByExample(examples, runner.results);
  const files = groups.filter(group => group.id !== CONTRACT_GROUP.id);
  const own = files.filter(group => group.primary.length > 0).length;
  const borrowed = files.filter(group => group.primary.length === 0 && group.secondary.length > 0).length;
  const delta =
    runner.cycleCountStart === null || runner.cycleCountEnd === null
      ? null
      : runner.cycleCountEnd - runner.cycleCountStart;

  // Closes the ticker line.
  say('');

  printReport(groups, runner.findings);

  say('\nSummary');
  say(
    `  ${counts.total} checks: ${counts.pass} passed, ${counts.fail} failed, ` +
      `${counts.warn} warned, ${counts.skip} skipped`,
  );
  say(
    `  ${files.length} example files: ${own} checked here, ${borrowed} checked under another, ` +
      `${files.length - own - borrowed} with no check`,
  );
  say(`  ${runner.requestsSent} HTTP requests · ${runner.checksSpent} checks budgeted`);
  say(
    `  billing-cycle counter: ${runner.cycleCountStart ?? 'n/a'} → ${runner.cycleCountEnd ?? 'n/a'}` +
      (delta === null ? '' : `  (+${delta} actually billed)`),
  );
  say(`  ${Date.now() - startedAt}ms · SDK ${VERSION}`);

  process.exit(exitCode);
}

// A run stopped halfway still paid for everything it sent, so it still reports.
process.on('SIGINT', () => finish(130));

// The report cannot start until the last check is done, so the ticker is what
// says the run is alive: one mark per check, in the order they run.
process.stdout.write('Running       ');

for (const check of plan) {
  await runner.run(check);

  process.stdout.write(STATUS[runner.results.at(-1).status]);
}

finish(runner.results.some(result => result.status === 'fail') ? 1 : 0);
