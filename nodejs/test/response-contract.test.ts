/**
 * `src/response-contract.json` restates, in the token vocabulary the live smoke
 * test speaks, what `src/types.ts` declares. Two files saying the same thing can
 * disagree, and a contract that has drifted from the types it claims to mirror
 * would check a live deployment against a promise the package no longer makes.
 *
 * These tests hold them together: same fields, and every token justified by the
 * declared type. Adding a field to `Nonprofit` fails here until the contract
 * learns about it, which is the point — a new field is a new prediction.
 */
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import ts from 'typescript';
import { describe, expect, it } from 'vitest';

interface ResponseContract {
  note: string;
  envelope: Record<string, string>;
  errorDetail: Record<string, string>;
  nonprofit: Record<string, string>;
  organizationType: Record<string, string>;
}

const contract = JSON.parse(
  readFileSync(fileURLToPath(new URL('../src/response-contract.json', import.meta.url)), 'utf8'),
) as ResponseContract;

const typesPath = fileURLToPath(new URL('../src/types.ts', import.meta.url));

const source = ts.createSourceFile(
  typesPath,
  readFileSync(typesPath, 'utf8'),
  ts.ScriptTarget.ES2022,
  true,
);

/**
 * Declared members of an interface, as field name to the source text of its
 * type. The index signature is skipped: `[key: string]: unknown` is what makes
 * an unpredicted field readable, not a field the package predicts.
 */
function declaredMembers(name: string): Map<string, string> {
  const members = new Map<string, string>();

  for (const statement of source.statements) {
    if (!ts.isInterfaceDeclaration(statement) || statement.name.text !== name) {
      continue;
    }

    for (const member of statement.members) {
      if (ts.isPropertySignature(member) && member.type && ts.isIdentifier(member.name)) {
        members.set(member.name.text, member.type.getText(source));
      }
    }
  }

  expect(members.size, `interface ${name} was not found in types.ts`).toBeGreaterThan(0);

  return members;
}

/** The token kinds a declared TypeScript type permits. */
function permittedBy(declared: string): Set<string> {
  const permitted = new Set<string>();

  for (const part of declared.split('|').map(one => one.trim())) {
    if (part === 'null') {
      permitted.add('null');
    } else if (part === 'boolean' || part === 'number') {
      permitted.add(part);
    } else if (part === 'string') {
      permitted.add('string');
    } else if (part.endsWith('[]')) {
      permitted.add('array');
    } else {
      permitted.add('object');
    }
  }

  return permitted;
}

const STRING_TOKENS = new Set(['string', 'text', 'date', 'date:iso', 'url', 'ofac-sentence', 'empty']);

/** Whether one contract token is justified by the declared type. */
function justified(token: string, permitted: Set<string>): boolean {
  if (STRING_TOKENS.has(token) || token.startsWith('digits:')) {
    return permitted.has('string');
  }

  return permitted.has(token);
}

const SHAPES: ReadonlyArray<[keyof ResponseContract & string, string]> = [
  ['envelope', 'ApiEnvelope'],
  ['errorDetail', 'ApiErrorDetail'],
  ['nonprofit', 'Nonprofit'],
  ['organizationType', 'OrganizationType'],
];

describe('response contract', () => {
  it.each(SHAPES)('%s predicts exactly the fields %s declares', (shape, interfaceName) => {
    const declared = [...declaredMembers(interfaceName).keys()]
      // `data` is the envelope's generic slot; each endpoint fills it, so the
      // contract supplies it at composition rather than declaring it once here.
      .filter(field => !(interfaceName === 'ApiEnvelope' && field === 'data'))
      .sort();

    expect(Object.keys(contract[shape] as Record<string, string>).sort()).toEqual(declared);
  });

  it.each(SHAPES)('%s tokens are all justified by %s', (shape, interfaceName) => {
    const declared = declaredMembers(interfaceName);

    for (const [field, allowed] of Object.entries(contract[shape] as Record<string, string>)) {
      const type = declared.get(field);

      expect(type, `${field} is in the contract but not in ${interfaceName}`).toBeDefined();

      const permitted = permittedBy(type as string);

      for (const token of allowed.split('|')) {
        expect(
          justified(token, permitted),
          `${interfaceName}.${field} is declared \`${type}\`, which permits no ${token} value`,
        ).toBe(true);
      }
    }
  });

  it('marks a field nullable exactly when the declared type does', () => {
    for (const [shape, interfaceName] of SHAPES) {
      const declared = declaredMembers(interfaceName);

      for (const [field, allowed] of Object.entries(contract[shape] as Record<string, string>)) {
        const type = declared.get(field) as string;

        expect(
          allowed.split('|').includes('null'),
          `${interfaceName}.${field} is declared \`${type}\` but the contract says \`${allowed}\``,
        ).toBe(permittedBy(type).has('null'));
      }
    }
  });
});
