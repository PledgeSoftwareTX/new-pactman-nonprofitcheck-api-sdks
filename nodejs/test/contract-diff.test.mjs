/**
 * `scripts/contract.mjs` decides what counts as the API having changed, and the
 * live smoke test fails a run on its answer. The rules that are easy to get
 * subtly wrong are the ones about absence: a field that is missing because it
 * was removed, versus one that is missing because the object it lives in
 * arrived null. Getting that backwards either fails every green run or passes
 * every broken one, and neither is visible without a live deployment to try it
 * against — so it is pinned here.
 */
import { describe, expect, it } from 'vitest';

import {
  baselineDiff,
  composeExpected,
  coverageDiff,
  schemaDiff,
  typeDiff,
} from '../scripts/contract.mjs';

/** The smallest expectation that still has a nested object and an array in it. */
const expected = {
  code: 'number',
  data: 'null|object',
  'data.ein': 'digits:9',
  'data.organization_types': 'array|null',
  'data.organization_types[]': 'object',
  'data.organization_types[].organization_type': 'null|string',
  errors: 'array|null|string',
  'errors[]': 'object',
  'errors[].reason': 'string',
};

/** A successful response: no errors, and this organization has no types. */
const success = {
  code: 'number',
  data: 'object',
  'data.ein': 'digits:9',
  'data.organization_types': 'null',
  errors: 'null',
};

describe('coverageDiff', () => {
  it('passes a response whose absent paths all sit under a null parent', () => {
    const result = coverageDiff(expected, success);

    expect(result.changes).toEqual([]);
    expect(result.total).toBe(0);
    // errors[], errors[].reason, organization_types[] and its one field.
    expect(result.unreachable).toBe(4);
  });

  it('fails a field that went missing while its parent was there', () => {
    const withoutEin = { ...success };

    delete withoutEin['data.ein'];

    const result = coverageDiff(expected, withoutEin);

    expect(result.total).toBe(1);
    expect(result.changes).toEqual([
      { kind: 'removed', path: 'data.ein', token: 'digits:9' },
    ]);
  });

  it('fails a field the API invented', () => {
    const result = coverageDiff(expected, { ...success, 'data.new_field': 'text' });

    expect(result.changes).toEqual([
      { kind: 'added', path: 'data.new_field', token: 'text' },
    ]);
  });

  it('reports a container that vanished once, not once per field under it', () => {
    const result = coverageDiff(expected, { code: 'number', errors: 'null' });

    expect(result.changes).toEqual([{ kind: 'removed', path: 'data', token: 'null|object' }]);
  });

  it('treats an array that arrived empty as having no room for its elements', () => {
    const result = coverageDiff(expected, { ...success, 'data.organization_types': 'array' });

    expect(result.total).toBe(0);
  });

  it('fails a field missing from the elements an array did return', () => {
    const result = coverageDiff(expected, {
      ...success,
      'data.organization_types': 'array',
      'data.organization_types[]': 'object',
    });

    expect(result.changes).toEqual([
      {
        kind: 'removed',
        path: 'data.organization_types[].organization_type',
        token: 'null|string',
      },
    ]);
  });
});

describe('the recorded baseline', () => {
  const recorded = { code: 'number', 'data.ein': 'digits:9', 'data.city': 'text' };

  it('reports a path that appeared and a path that disappeared', () => {
    const now = { code: 'number', 'data.ein': 'digits:9', 'data.county': 'text' };

    expect(schemaDiff(recorded, now).changes).toEqual([
      { kind: 'removed', path: 'data.city', token: 'text' },
      { kind: 'added', path: 'data.county', token: 'text' },
    ]);
  });

  it('reports a value whose form moved, on a path both have', () => {
    const now = { ...recorded, 'data.ein': 'digits:2-7' };

    expect(typeDiff(recorded, now).changes).toEqual([
      { kind: 'changed', path: 'data.ein', from: 'digits:9', to: 'digits:2-7' },
    ]);
  });

  it('sees no difference in an identical signature', () => {
    expect(schemaDiff(recorded, { ...recorded }).total).toBe(0);
    expect(typeDiff(recorded, { ...recorded }).total).toBe(0);
  });
});

describe('baselineDiff', () => {
  /** One organization, recorded on an afternoon its Pub 78 row was populated. */
  const recorded = {
    code: 'number',
    'data.ein': 'digits:9',
    'data.pub78_city': 'text',
    'data.organization_types': 'array',
    'data.organization_types[]': 'object',
    'data.organization_types[].organization_type': 'text',
    errors: 'null',
  };

  it('passes a subject whose nullable fields came back empty this time', () => {
    const now = {
      code: 'number',
      'data.ein': 'digits:9',
      'data.pub78_city': 'null',
      'data.organization_types': 'null',
      errors: 'null',
    };

    const result = baselineDiff(recorded, now);

    expect(result.changes).toEqual([]);
    expect(result.nullable).toBe(2);
    // organization_types[] and the one field under it.
    expect(result.unreachable).toBe(2);
  });

  it('passes a field that filled in since the recording', () => {
    const result = baselineDiff({ 'data.pub78_city': 'null' }, { 'data.pub78_city': 'text' });

    expect(result.changes).toEqual([]);
    expect(result.nullable).toBe(1);
  });

  it('passes a token that only gained or lost null', () => {
    const result = baselineDiff(
      { 'data[].address_line2': 'digits:4|null' },
      { 'data[].address_line2': 'digits:4' },
    );

    expect(result.changes).toEqual([]);
    expect(result.nullable).toBe(1);
  });

  it('passes the paths under a parent that was null when it was recorded', () => {
    const result = baselineDiff(
      { errors: 'null' },
      { errors: 'array', 'errors[]': 'object', 'errors[].code': 'number' },
    );

    expect(result.changes).toEqual([]);
    expect(result.unreachable).toBe(2);
  });

  it('still fails a value whose form moved between two real forms', () => {
    const result = baselineDiff({ 'data.ein': 'digits:9' }, { 'data.ein': 'text' });

    expect(result.changes).toEqual([
      { kind: 'changed', path: 'data.ein', from: 'digits:9', to: 'text' },
    ]);
    expect(result.nullable).toBe(0);
  });

  it('still fails a form that moved while the field also turned nullable', () => {
    const result = baselineDiff({ 'data.ein': 'digits:9' }, { 'data.ein': 'null|text' });

    expect(result.changes).toEqual([
      { kind: 'changed', path: 'data.ein', from: 'digits:9', to: 'null|text' },
    ]);
  });

  it('still fails a field that vanished while its parent was there', () => {
    const now = { ...recorded };

    delete now['data.ein'];

    expect(baselineDiff(recorded, now).changes).toEqual([
      { kind: 'removed', path: 'data.ein', token: 'digits:9' },
    ]);
  });

  it('still fails a field the API invented', () => {
    const result = baselineDiff(recorded, { ...recorded, 'data.county': 'text' });

    expect(result.changes).toEqual([{ kind: 'added', path: 'data.county', token: 'text' }]);
  });
});

describe('composeExpected', () => {
  it('describes the record under data for single and under data[] for bulk', () => {
    const contract = {
      envelope: { code: 'number', errors: 'array|null|string' },
      errorDetail: { reason: 'string' },
      nonprofit: { ein: 'digits:9|null' },
      organizationType: { organization_type: 'null|string' },
    };

    expect(composeExpected(contract, 'single')['data.ein']).toBe('digits:9|null');
    expect(composeExpected(contract, 'bulk')['data[].ein']).toBe('digits:9|null');
    expect(composeExpected(contract, 'single').data).toBe('null|object');
    expect(composeExpected(contract, 'bulk').data).toBe('array|null');
  });

  it('lets an element of organization_types be null', () => {
    const contract = {
      envelope: {},
      errorDetail: {},
      nonprofit: {},
      organizationType: { organization_type: 'null|string' },
    };

    expect(composeExpected(contract, 'single')['data.organization_types[]']).toBe('null|object');
    expect(composeExpected(contract, 'bulk')['data[].organization_types[]']).toBe('null|object');
  });
});
