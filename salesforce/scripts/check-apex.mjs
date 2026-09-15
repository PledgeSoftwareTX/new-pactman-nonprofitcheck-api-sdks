#!/usr/bin/env node
/**
 * Offline checks over every Apex class in this project.
 *
 * A scratch org is the only real compiler for Apex, and CI only gets one when
 * SF_DEVHUB_AUTH_URL is configured. These checks need neither, so they run on
 * every push and catch the mistakes that would otherwise burn a scratch-org
 * deploy twenty minutes later:
 *
 *   1. Syntax, through the same ANTLR grammar the Apex tooling uses. This is
 *      what catches a method named after a reserved word — `merge`, `insert`,
 *      `system` — which reads perfectly and does not parse.
 *   2. Every `Type.member` reference in the examples resolving to a member the
 *      SDK actually declares. A syntax parse is happy with `Sources.pub78(x)`;
 *      the SDK only has `getPub78`.
 *
 * Neither is a substitute for `sf project deploy start`. They are the part of
 * it that can run in four seconds without an org.
 */

import { readdirSync, readFileSync, statSync } from 'node:fs';
import { dirname, join, relative } from 'node:path';
import { fileURLToPath } from 'node:url';
import { check } from '@apexdevtools/apex-parser';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const sourceDirs = ['force-app', 'examples-app'];

/** Members every Apex exception inherits from the platform. */
const EXCEPTION_MEMBERS = new Set([
  'getMessage',
  'getStackTraceString',
  'getTypeName',
  'getCause',
  'getLineNumber',
  'setMessage',
  'initCause',
]);

const failures = [];

function classFiles(dir) {
  const found = [];

  for (const entry of readdirSync(dir)) {
    const path = join(dir, entry);

    if (statSync(path).isDirectory()) {
      found.push(...classFiles(path));
    } else if (entry.endsWith('.cls')) {
      found.push(path);
    }
  }

  return found;
}

/** Removes comments and string literals so neither contributes a reference. */
function strip(source) {
  return source
    .replace(/\/\*[\s\S]*?\*\//g, ' ')
    .replace(/\/\/[^\n]*/g, ' ')
    .replace(/'(?:[^'\\]|\\.)*'/g, "''");
}

// ---------------------------------------------------------------- 1. syntax

for (const dir of sourceDirs) {
  const result = await check(join(root, dir), '.cls');

  for (const error of result.errors ?? []) {
    failures.push(
      `${dir}/${error.path}:${error.line}:${error.column} — ${String(error.message).slice(0, 120)}`,
    );
  }
}

// ------------------------------------------------------------- 2. references

const files = sourceDirs.flatMap(dir => classFiles(join(root, dir)));

/** class -> members it declares itself */
const declared = new Map();
/** class -> the class it extends */
const extended = new Map();
/** enum -> its values */
const enums = new Map();

for (const file of files) {
  const source = strip(readFileSync(file, 'utf8'));
  const name = file.split('/').pop().replace(/\.cls$/, '');

  const asEnum = source.match(/\benum\s+(\w+)\s*\{([^}]*)\}/i);

  if (asEnum) {
    enums.set(
      asEnum[1],
      new Set(
        asEnum[2]
          .split(',')
          .map(value => value.trim())
          .filter(Boolean),
      ),
    );
    continue;
  }

  const parent = source.match(new RegExp(`\\bclass\\s+${name}\\s+extends\\s+(\\w+)`, 'i'));

  if (parent) {
    extended.set(name, parent[1]);
  }

  const members = new Set();

  for (const member of source.matchAll(
    /\b(?:global|public|protected|private)\s+(?:static\s+)?(?:final\s+)?(?:override\s+)?[\w<>,.[\] ]+?\s+(\w+)\s*[({;=]/g,
  )) {
    members.add(member[1]);
  }

  for (const nested of source.matchAll(/\b(?:class|interface)\s+(\w+)/gi)) {
    members.add(nested[1]);
  }

  declared.set(name, members);
}

/** Every member visible on a type, following the extends chain. */
function membersOf(type) {
  const visible = new Set();
  let current = type;

  while (current) {
    if (current === 'Exception') {
      for (const member of EXCEPTION_MEMBERS) visible.add(member);
      break;
    }

    if (!declared.has(current)) break;

    for (const member of declared.get(current)) visible.add(member);
    current = extended.get(current);
  }

  return visible;
}

const types = new Set([...declared.keys()]);
const problems = new Set();

for (const file of classFiles(join(root, 'examples-app'))) {
  const source = strip(readFileSync(file, 'utf8'));
  const where = relative(root, file);

  // Static and enum references.
  for (const [, type, member] of source.matchAll(/\b([A-Z]\w+)\.(\w+)/g)) {
    if (enums.has(type)) {
      if (!enums.get(type).has(member)) {
        problems.add(`${where}: ${type}.${member} is not a value of enum ${type}`);
      }
      continue;
    }

    if (!types.has(type)) continue; // A platform type; not ours to check.

    const visible = membersOf(type);

    if (visible.size > 0 && !visible.has(member)) {
      problems.add(`${where}: ${type}.${member} is not declared on ${type}`);
    }
  }

  // Instance references, for locals declared with an explicit SDK type.
  const typeOf = new Map();

  for (const type of types) {
    for (const [, name] of source.matchAll(new RegExp(`\\b${type}\\s+(\\w+)\\s*[=;,)]`, 'g'))) {
      typeOf.set(name, type);
    }

    for (const [, name] of source.matchAll(new RegExp(`for\\s*\\(\\s*${type}\\s+(\\w+)\\s*:`, 'g'))) {
      typeOf.set(name, type);
    }
  }

  for (const [, name, member] of source.matchAll(/\b([a-z]\w*)\.(\w+)/g)) {
    const type = typeOf.get(name);

    if (!type) continue;

    const visible = membersOf(type);

    if (visible.size > 0 && !visible.has(member)) {
      problems.add(`${where}: ${name} (${type}).${member} is not declared on ${type}`);
    }
  }
}

failures.push(...problems);

// ------------------------------------------------------------------- report

if (failures.length > 0) {
  console.error('Apex checks failed:\n');
  for (const failure of failures) console.error(`  - ${failure}`);
  process.exit(1);
}

console.log(
  `Apex OK — ${files.length} classes parsed, ` +
    `${types.size} types and ${enums.size} enums resolved.`,
);
