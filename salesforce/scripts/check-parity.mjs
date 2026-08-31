#!/usr/bin/env node
/**
 * The parity checks the other SDKs get from unit tests.
 *
 * Node asserts `src/version.ts` against `package.json`, and Python asserts
 * `version.py` against `pyproject.toml`, inside their own test suites. Apex
 * cannot read `sfdx-project.json` at runtime, so the equivalent assertions run
 * here instead — and CI is the only thing standing between a mismatch and a
 * promoted, immutable package version.
 *
 * Checks:
 *   1. SdkVersion.VERSION matches the major.minor.patch in sfdx-project.json.
 *   2. Nonprofit.cls declares exactly the fields in the response contract.
 *   3. The packaged contract copy is byte-identical to the Node source of truth.
 */

import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';

const here = dirname(fileURLToPath(import.meta.url));
const root = resolve(here, '..');
const read = path => readFileSync(resolve(root, path), 'utf8');

const failures = [];
const fail = message => failures.push(message);

// 1. Version parity.
const project = JSON.parse(read('sfdx-project.json'));
const declared = project.packageDirectories[0].versionNumber.split('.').slice(0, 3).join('.');
const source = read('force-app/main/default/classes/SdkVersion.cls').match(
  /VERSION\s*=\s*'([^']+)'/,
);

if (!source) {
  fail('Could not find VERSION in SdkVersion.cls.');
} else if (source[1] !== declared) {
  fail(`SdkVersion.VERSION is ${source[1]} but sfdx-project.json says ${declared}.`);
}

// 2 and 3. Contract parity, against the Node SDK's copy as the source of truth.
const canonicalPath = '../nodejs/src/response-contract.json';
const packagedPath = 'force-app/main/default/staticresources/pactman_response_contract.json';
const canonical = read(canonicalPath);

if (canonical !== read(packagedPath)) {
  fail(
    `${packagedPath} has drifted from ${canonicalPath}. Copy the Node file over it — ` +
      'the Node SDK is the source of truth for the contract.',
  );
}

const contractFields = Object.keys(JSON.parse(canonical).nonprofit);
const nonprofit = read('force-app/main/default/classes/Nonprofit.cls');
const declaredFields = new Set(
  [...nonprofit.matchAll(/global (?:String|Boolean|List<OrganizationType>) (\w+) \{/g)].map(
    match => match[1],
  ),
);

const missing = contractFields.filter(field => !declaredFields.has(field));
const extra = [...declaredFields].filter(field => !contractFields.includes(field));

if (missing.length > 0) {
  fail(`Nonprofit.cls is missing accessors the contract declares: ${missing.join(', ')}.`);
}

if (extra.length > 0) {
  fail(`Nonprofit.cls declares accessors the contract does not: ${extra.join(', ')}.`);
}

if (failures.length > 0) {
  console.error('Parity check failed:\n');
  for (const message of failures) console.error(`  - ${message}`);
  process.exit(1);
}

console.log(
  `Parity OK — version ${declared}, ${contractFields.length} contract fields, packaged contract in sync.`,
);
