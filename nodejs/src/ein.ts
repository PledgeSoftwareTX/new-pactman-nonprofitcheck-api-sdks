/**
 * EIN normalization and validation.
 *
 * Formatting validation only. Passing these checks says nothing about whether an
 * organization is tax-exempt, in good standing, or eligible for anything — only
 * that the value is shaped like an EIN. No IRS prefix rules are applied.
 */

import { PactmanValidationError, type ValidationIssue } from './errors.js';

/** Number of digits in an EIN. */
export const EIN_LENGTH = 9;

/**
 * Accepted input shapes: nine digits, optionally with the conventional hyphen
 * after the two-digit prefix. Surrounding whitespace is ignored.
 */
const EIN_PATTERN = /^\d{2}-?\d{7}$/;

/**
 * Normalizes an EIN to the nine-digit form the API expects.
 *
 * `"41-1787097"` and `"411787097"` both normalize to `"411787097"`.
 *
 * @throws {PactmanValidationError} if the value is not shaped like an EIN.
 */
export function normalizeEin(input: unknown, index?: number): string {
  const issue = einIssue(input, index);

  if (issue) {
    throw new PactmanValidationError(issue.message, [issue]);
  }

  return (input as string).trim().replace('-', '');
}

/**
 * Normalizes a collection of EINs, reporting every failure at once.
 *
 * Duplicates are preserved and order is retained; see `checkBulk` for the
 * optional `dedupe` behaviour.
 *
 * @throws {PactmanValidationError} if any item is not shaped like an EIN. The
 * error's `issues` identify the failing item by index and original value.
 */
export function normalizeEins(inputs: readonly unknown[]): string[] {
  const issues: ValidationIssue[] = [];
  const normalized: string[] = [];

  inputs.forEach((input, index) => {
    const issue = einIssue(input, index);

    if (issue) {
      issues.push(issue);
      return;
    }

    normalized.push((input as string).trim().replace('-', ''));
  });

  if (issues.length > 0) {
    const positions = issues.map(issue => issue.index).join(', ');
    throw new PactmanValidationError(
      `${issues.length} of ${inputs.length} EINs are invalid (at index ${positions}). No request was sent.`,
      issues,
    );
  }

  return normalized;
}

/** True when `input` is shaped like an EIN. Never throws. */
export function isValidEin(input: unknown): boolean {
  return einIssue(input) === null;
}

function einIssue(input: unknown, index?: number): ValidationIssue | null {
  const at = index === undefined ? '' : ` at index ${index}`;

  if (input === null || input === undefined) {
    return { message: `EIN${at} is required.`, index, value: input };
  }

  if (typeof input !== 'string') {
    return {
      message: `EIN${at} must be a string, received ${typeof input}.`,
      index,
      value: input,
    };
  }

  const trimmed = input.trim();

  if (trimmed === '') {
    return { message: `EIN${at} is empty.`, index, value: input };
  }

  if (!EIN_PATTERN.test(trimmed)) {
    return {
      message:
        `EIN${at} must be ${EIN_LENGTH} digits, optionally hyphenated as XX-XXXXXXX. ` +
        `Received "${trimmed}".`,
      index,
      value: input,
    };
  }

  return null;
}
