/**
 * Rewrites `VERSION` in src/version.ts to match package.json.
 *
 * Runs from npm's `version` lifecycle hook, so `npm version <x>` keeps the
 * User-Agent string in step with the published version. A unit test asserts the
 * two agree, so drift fails the build rather than shipping quietly.
 */
import { readFileSync, writeFileSync } from 'node:fs';

const VERSION_FILE = new URL('../src/version.ts', import.meta.url);

const { version } = JSON.parse(readFileSync(new URL('../package.json', import.meta.url), 'utf8'));
const source = readFileSync(VERSION_FILE, 'utf8');
const updated = source.replace(/export const VERSION = '[^']*';/, `export const VERSION = '${version}';`);

if (updated === source) {
  console.log(`src/version.ts already at ${version}.`);
} else {
  writeFileSync(VERSION_FILE, updated);
  console.log(`src/version.ts updated to ${version}.`);
}
