/**
 * Runs every example against the mock server and fails if any of them errors.
 *
 * This is what CI uses to keep the documented examples honest. Requires a build,
 * because the examples import the package by name.
 *
 * Pass a filter to run a subset: `node scripts/run-examples-against-mock.mjs 22 23`
 */
import { spawn } from 'node:child_process';
import { readdirSync } from 'node:fs';
import { startMockServer } from './mock-server.mjs';

const EXAMPLES_DIR = new URL('../examples/', import.meta.url);
const API_KEY = 'mock-key';
const PER_EXAMPLE_TIMEOUT_MS = 60_000;

/** Numbered examples first, then the originals, so failures read in order. */
function discoverExamples() {
  const files = readdirSync(EXAMPLES_DIR)
    .filter(name => name.endsWith('.mjs'))
    .sort();

  const numbered = files.filter(name => /^ex-\d{2}-/.test(name));
  const others = files.filter(name => !/^ex-\d{2}-/.test(name));

  return [...numbered, ...others].map(name => `examples/${name}`);
}

function run(script, env) {
  return new Promise((resolve, reject) => {
    const child = spawn(process.execPath, [script], {
      env: { ...process.env, ...env },
      stdio: ['ignore', 'pipe', 'pipe'],
    });

    let output = '';
    child.stdout.on('data', chunk => (output += chunk));
    child.stderr.on('data', chunk => (output += chunk));

    const timer = setTimeout(() => {
      child.kill('SIGKILL');
      reject(new Error(`${script} did not finish within ${PER_EXAMPLE_TIMEOUT_MS}ms\n${output}`));
    }, PER_EXAMPLE_TIMEOUT_MS);

    child.on('close', code => {
      clearTimeout(timer);

      if (code === 0) {
        resolve(output);
        return;
      }

      reject(new Error(`${script} exited with code ${code}\n${output}`));
    });
  });
}

const filters = process.argv.slice(2);
const examples = discoverExamples().filter(
  name => filters.length === 0 || filters.some(filter => name.includes(filter)),
);

const fixture = await startMockServer({ apiKey: API_KEY });
const verbose = process.env.EXAMPLES_VERBOSE === '1';
const failures = [];

console.log(`Running ${examples.length} examples against ${fixture.url}\n`);

try {
  for (const example of examples) {
    try {
      const output = await run(example, {
        PACTMAN_API_KEY: API_KEY,
        PACTMAN_BASE_URL: fixture.url,
      });

      // The one assertion this harness makes about content: no example may print
      // the credential it was given.
      if (output.includes(API_KEY)) {
        throw new Error(`${example} printed the API key.`);
      }

      console.log(`✓ ${example}`);

      if (verbose) {
        console.log(
          output
            .trimEnd()
            .split('\n')
            .map(line => `    ${line}`)
            .join('\n'),
        );
      }
    } catch (error) {
      failures.push(example);
      console.error(`✗ ${error.message}`);
    }
  }
} finally {
  fixture.close();
}

console.log(`\n${examples.length - failures.length}/${examples.length} examples passed.`);

if (failures.length > 0) {
  console.error(`Failed: ${failures.join(', ')}`);
  process.exit(1);
}
