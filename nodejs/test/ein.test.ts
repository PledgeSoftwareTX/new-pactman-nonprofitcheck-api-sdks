import { describe, expect, it } from 'vitest';
import { isValidEin, normalizeEin, normalizeEins } from '../src/ein.js';
import { PactmanValidationError } from '../src/errors.js';

describe('normalizeEin', () => {
  it('normalizes hyphenated and bare EINs to the same value', () => {
    expect(normalizeEin('41-1787097')).toBe('411787097');
    expect(normalizeEin('411787097')).toBe('411787097');
  });

  it('ignores surrounding whitespace', () => {
    expect(normalizeEin('  41-1787097  ')).toBe('411787097');
  });

  it.each([
    ['eight digits', '41178709'],
    ['ten digits', '4117870971'],
    ['letters', '41-178709A'],
    ['all letters', 'abcdefghi'],
    ['unsupported punctuation', '41.1787097'],
    ['a hyphen in the wrong place', '4117-87097'],
    ['spaces inside', '41 1787097'],
    ['empty', ''],
    ['whitespace only', '   '],
  ])('rejects %s', (_label, value) => {
    expect(() => normalizeEin(value)).toThrowError(PactmanValidationError);
    expect(isValidEin(value)).toBe(false);
  });

  it.each([
    ['null', null],
    ['undefined', undefined],
    ['a number', 411787097],
  ])('rejects %s', (_label, value) => {
    expect(() => normalizeEin(value)).toThrowError(PactmanValidationError);
    expect(isValidEin(value)).toBe(false);
  });

  it('names the offending value without leaking configuration', () => {
    try {
      normalizeEin('41178709');
      expect.unreachable('an eight-digit EIN should throw');
    } catch (error) {
      expect(error).toBeInstanceOf(PactmanValidationError);
      const validation = error as PactmanValidationError;

      expect(validation.message).toContain('41178709');
      expect(validation.origin).toBe('local');
      expect(validation.issues[0]?.value).toBe('41178709');
    }
  });
});

describe('normalizeEins', () => {
  it('preserves order and duplicates', () => {
    expect(normalizeEins(['41-1787097', '996589560', '411787097'])).toEqual([
      '411787097',
      '996589560',
      '411787097',
    ]);
  });

  it('identifies which item failed, by index and value', () => {
    try {
      normalizeEins(['411787097', 'nope', '996589560', '1234']);
      expect.unreachable('invalid items should throw');
    } catch (error) {
      expect(error).toBeInstanceOf(PactmanValidationError);
      const validation = error as PactmanValidationError;

      expect(validation.issues).toHaveLength(2);
      expect(validation.issues.map(issue => issue.index)).toEqual([1, 3]);
      expect(validation.issues[0]?.value).toBe('nope');
      expect(validation.message).toContain('index 1, 3');
    }
  });
});
