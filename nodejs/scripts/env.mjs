/**
 * The `.env` beside the package, read by every script that needs a live key.
 *
 * Kept here rather than in one script so `smoke-live.mjs` and
 * `record-baseline.mjs` read the same file the same way — the two have to agree
 * on which deployment and which subjects they are talking about, and a second
 * copy of this parser is how they would stop agreeing.
 */
import { existsSync, readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

/** The variable the credential is read from, in the environment or in `.env`. */
export const API_KEY_ENV = 'PACTMAN_API_KEY';

/**
 * How many of the bulk subjects a run actually sends.
 *
 * The bulk probes read the first few and the rest would cost quota unspent —
 * but the recorder has to send the same batch the smoke run does. A signature
 * collapses every element of `data[]` onto one path, so a five-EIN recording
 * and a three-EIN run disagree wherever the two extra organizations carry a
 * value the first three do not. Same number, same subjects, or the comparison
 * reports the batch size as drift.
 */
export const BULK_PROBE_LIMIT = 3;

/**
 * Loads `nodejs/.env`, so the key and any standing overrides live in a file
 * rather than in the shell for every run. The file is gitignored.
 *
 * A variable already in the environment wins: exporting one for a single run
 * must not be silently overridden by a file someone set up months ago.
 */
export function loadEnvFile() {
  const path = fileURLToPath(new URL('../.env', import.meta.url));

  if (!existsSync(path)) {
    return null;
  }

  const names = new Set();

  // Both line endings: a .env saved on Windows ends its lines with CRLF, and
  // `.` in the pattern below does not match the CR, so every line would fail
  // to parse and a file full of variables would look empty.
  for (const line of readFileSync(path, 'utf8').split(/\r?\n/)) {
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
