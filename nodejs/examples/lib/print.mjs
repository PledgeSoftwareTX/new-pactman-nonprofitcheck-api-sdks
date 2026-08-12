/**
 * Console formatting for the examples.
 *
 * The important rule here is {@link render}: a field the API returned as `null`
 * and a field the API did not return at all print differently. Collapsing them
 * into `""` or `"-"` is how a missing value quietly becomes a match.
 */

export function heading(text) {
  console.log(`\n${text}`);
  console.log('─'.repeat(text.length));
}

/** `<null>` for an explicit null, `<not returned>` for an absent key. */
export function render(value) {
  if (value === undefined) {
    return '<not returned>';
  }

  if (value === null) {
    return '<null>';
  }

  if (Array.isArray(value)) {
    return value.length === 0 ? '<empty list>' : `${value.length} entries`;
  }

  return String(value);
}

export function field(label, value, width = 32) {
  console.log(`  ${String(label).padEnd(width)} ${render(value)}`);
}

export function bullet(text) {
  console.log(`  • ${text}`);
}

/** A short, single-line note. Used for policy statements and caveats. */
export function note(text) {
  console.log(`\n${text}`);
}
