/**
 * Runs every example against the mock server and fails if any of them errors.
 *
 * This is what CI uses to keep the README's examples honest. Requires a build,
 * because the examples import the package by name.
 */
import { spawn } from 'node:child_process';
import { startMockServer } from './mock-server.mjs';

const EXAMPLES = ['examples/quickstart.mjs', 'examples/bulk.mjs', 'examples/error-handling.mjs'];

function run(script, env) {
  return new Promise((resolve, reject) => {
    const child = spawn(process.execPath, [script], {
      env: { ...process.env, ...env },
      stdio: ['ignore', 'pipe', 'pipe'],
    });

    let output = '';
    child.stdout.on('data', chunk => (output += chunk));
    child.stderr.on('data', chunk => (output += chunk));

    child.on('close', code => {
      if (code === 0) {
        resolve(output);
        return;
      }

      reject(new Error(`${script} exited with code ${code}\n${output}`));
    });
  });
}

const { server, url } = await startMockServer();
let failed = false;

try {
  for (const example of EXAMPLES) {
    const output = await run(example, { PACTMAN_API_KEY: 'mock-key', PACTMAN_BASE_URL: url });

    if (output.includes('mock-key')) {
      throw new Error(`${example} printed the API key.`);
    }

    console.log(`✓ ${example}`);
    console.log(
      output
        .trimEnd()
        .split('\n')
        .map(line => `    ${line}`)
        .join('\n'),
    );
  }
} catch (error) {
  failed = true;
  console.error(`✗ ${error.message}`);
} finally {
  server.close();
}

process.exit(failed ? 1 : 0);
