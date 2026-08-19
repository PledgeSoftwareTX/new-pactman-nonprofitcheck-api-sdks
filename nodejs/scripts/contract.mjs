/**
 * Signatures of a JSON response, and the differences between two of them.
 *
 * A recorded copy of a live response is worthless as a drift detector: every
 * run returns a fresh `report_date`, a different `timeTaken` and a usage counter
 * that only goes up, so a byte comparison fails for reasons that have nothing to
 * do with the API changing. What is stable is the shape — which fields exist,
 * what type each carries, and what form its values take. That is what a
 * signature captures, and comparing one against a recorded baseline is how
 * `smoke-live.mjs` answers "has the API changed?" without re-recording every
 * time the IRS data behind an organization is refreshed.
 *
 * A signature is a flat, sorted map of path to type token:
 *
 *   {
 *     "code": "number",
 *     "data.ein": "digits:9",
 *     "data.most_recent_bmf": "date",
 *     "data.organization_types[].deductibility_limitation": "text",
 *     "data.pub78_verified": "boolean",
 *     "data.revocation_code": "null",
 *     "errors": "null"
 *   }
 *
 * Flat, so a field that appears, disappears or changes type is one line in a git
 * diff, and so comparing two signatures is a key-by-key walk rather than a
 * recursive descent that has to re-derive structure it already knows.
 *
 * The two halves are compared separately — {@link schemaDiff} over the paths,
 * {@link typeDiff} over the tokens — because they fail for different reasons and
 * mean different things. A field that disappeared breaks callers that read it; a
 * field that changed type breaks callers that parse it. Reporting them as one
 * number would say only that something moved.
 *
 * Tokens
 *   object, array, boolean, number, null   the JSON type, structural
 *   date            `M/D/YYYY h:mm:ss AM` — the format every API timestamp uses
 *   date:iso        an ISO-8601 timestamp, which this API does not currently send
 *   digits:9        a string of digits, grouped by length: "411787097" is
 *                   digits:9, "01085-2643" is digits:5-4, "00" is digits:2
 *   url             an http(s) URL
 *   ofac-sentence   the SDN sentence `ofac_status` carries, in either wording
 *   empty           an empty or whitespace-only string
 *   text            any other string
 *
 * A path that carries more than one token across a single response — a field
 * that is a date on one organization in a bulk batch and null on another —
 * records them sorted and joined by "|", as in `date|null`.
 *
 * Only shapes go in. No value from the response is ever recorded, so a baseline
 * is safe to commit and a diff is safe to print.
 */

/** The format every timestamp in this API uses. See `fixtures.mjs#apiDate`. */
const API_DATE = /^\d{1,2}\/\d{1,2}\/\d{4},? \d{1,2}:\d{2}:\d{2} ?(?:AM|PM)$/i;

const ISO_DATE = /^\d{4}-\d{2}-\d{2}(?:[T ]\d{2}:\d{2}|$)/;

/** Digits, optionally in hyphen-separated groups: EINs, ZIPs, IRS codes. */
const DIGIT_GROUPS = /^\d+(?:-\d+)*$/;

const URL_LIKE = /^https?:\/\//i;

/**
 * The clause both OFAC wordings share.
 *
 * Matching the clause rather than either whole sentence keeps a genuine change
 * of wording visible — it would fall back to `text` — while a subject that goes
 * from "was NOT included" to "may be included", or a possible match whose UID
 * differs, stays the same shape. That is a change in the data, not the contract.
 */
const OFAC_SENTENCE = /Specially Designated Nationals ?\(SDN\) list/i;

/** Classifies a string by the form of its value, never by the value itself. */
export function formatOf(value) {
  // Newer runtimes format times with a narrow no-break space; the API sends a
  // plain one. Normalize so the same timestamp is not two different tokens.
  const text = value.replace(/[  ]/g, ' ');

  if (text.trim() === '') {
    return 'empty';
  }

  if (API_DATE.test(text)) {
    return 'date';
  }

  if (ISO_DATE.test(text)) {
    return 'date:iso';
  }

  if (DIGIT_GROUPS.test(text)) {
    return `digits:${text
      .split('-')
      .map(group => group.length)
      .join('-')}`;
  }

  if (URL_LIKE.test(text)) {
    return 'url';
  }

  if (OFAC_SENTENCE.test(text)) {
    return 'ofac-sentence';
  }

  return 'text';
}

function tokenFor(value) {
  if (value === null) {
    return 'null';
  }

  if (Array.isArray(value)) {
    return 'array';
  }

  if (typeof value === 'string') {
    return formatOf(value);
  }

  if (typeof value === 'object') {
    return 'object';
  }

  return typeof value;
}

function isPlainObject(value) {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function collect(value, path, tokens) {
  if (path !== '') {
    const seen = tokens.get(path);

    if (seen === undefined) {
      tokens.set(path, new Set([tokenFor(value)]));
    } else {
      seen.add(tokenFor(value));
    }
  }

  // Every element of an array contributes to one path, so a batch of ten
  // organizations describes one record shape rather than ten.
  if (Array.isArray(value)) {
    for (const item of value) {
      collect(item, `${path}[]`, tokens);
    }

    return;
  }

  if (isPlainObject(value)) {
    for (const [key, child] of Object.entries(value)) {
      collect(child, path === '' ? key : `${path}.${key}`, tokens);
    }
  }
}

/** Builds the signature of a parsed JSON response. */
export function signatureOf(value) {
  const tokens = new Map();

  collect(value, '', tokens);

  return Object.fromEntries(
    [...tokens]
      .sort(([left], [right]) => (left < right ? -1 : left > right ? 1 : 0))
      .map(([path, set]) => [path, [...set].sort().join('|')]),
  );
}

/**
 * Fields the API stopped sending, and fields it started sending.
 *
 * Additions count. A field the API added is forward-compatible for a caller —
 * the SDK surfaces it through the index signature either way — but it is still
 * the API changing, and a baseline that quietly absorbs additions cannot tell
 * you when it did.
 */
export function schemaDiff(baseline, current) {
  const changes = [];

  for (const [path, token] of Object.entries(baseline)) {
    if (!Object.hasOwn(current, path)) {
      changes.push({ kind: 'removed', path, token });
    }
  }

  for (const [path, token] of Object.entries(current)) {
    if (!Object.hasOwn(baseline, path)) {
      changes.push({ kind: 'added', path, token });
    }
  }

  return { changes: sortChanges(changes), total: changes.length };
}

/**
 * Fields whose type or value format changed, across the paths both signatures
 * have. Paths only one of them has are {@link schemaDiff}'s to report, so a
 * single renamed field is one failure rather than two.
 */
export function typeDiff(baseline, current) {
  const changes = [];

  for (const [path, token] of Object.entries(baseline)) {
    if (Object.hasOwn(current, path) && current[path] !== token) {
      changes.push({ kind: 'changed', path, from: token, to: current[path] });
    }
  }

  return { changes: sortChanges(changes), total: changes.length };
}

/** Removals first: a field that disappeared breaks callers that read it. */
const CHANGE_ORDER = { removed: 0, changed: 1, added: 2 };

function sortChanges(changes) {
  return [...changes].sort(
    (left, right) =>
      CHANGE_ORDER[left.kind] - CHANGE_ORDER[right.kind] || left.path.localeCompare(right.path),
  );
}

/** "2 removed, 1 added" — the counts that are not zero. */
export function summarizeChanges(changes) {
  const counts = { removed: 0, changed: 0, added: 0 };

  for (const change of changes) {
    counts[change.kind] += 1;
  }

  const parts = Object.entries(counts)
    .filter(([, count]) => count > 0)
    .map(([kind, count]) => `${count} ${kind}`);

  return parts.length === 0 ? 'no differences' : parts.join(', ');
}

const MARKS = { removed: '-', changed: '~', added: '+' };

/** One line per change, indented to sit under a check's own line. */
export function formatChanges(changes, { indent = '      ', limit = 12 } = {}) {
  const lines = changes.map(change =>
    change.kind === 'changed'
      ? `~ ${change.path}: ${change.from} → ${change.to}`
      : `${MARKS[change.kind]} ${change.path} (${change.token})`,
  );

  const shown = lines.slice(0, limit);

  if (lines.length > shown.length) {
    shown.push(`… and ${lines.length - shown.length} more`);
  }

  return shown.map(line => `${indent}${line}`).join('\n');
}

// --- the package's own prediction -------------------------------------------

/**
 * Everything above compares one live response against another recorded earlier,
 * which answers "did the API move?" but never "does the API still match what
 * this package tells its users?". The second question is the one with a caller
 * on the other end of it: `src/types.ts` promises `bmf_status` is a boolean, and
 * a user writes `if (bmf.status)` on the strength of that promise. Nothing in a
 * self-recorded baseline can notice when the API disagrees, because the baseline
 * is the API's own output — it agrees with itself by construction.
 *
 * `src/response-contract.json` is the other side of that comparison: the shape
 * this package predicts, in the same token vocabulary as a signature so the two
 * can be held against each other directly. It is checked in, identical for
 * everyone, and derived from the declared types rather than from anyone's
 * account — so a diff to it is a deliberate change to what the SDK promises,
 * reviewable as such, rather than a record of what one organization looked like
 * on one afternoon.
 */

/** String tokens `string` stands for, when the package claims no format. */
const STRING_TOKENS = new Set(['text', 'date', 'date:iso', 'url', 'ofac-sentence', 'empty']);

function isStringToken(token) {
  return STRING_TOKENS.has(token) || token.startsWith('digits:');
}

/**
 * Whether an observed token is one the contract allows.
 *
 * `string` is a wildcard over every string token, because a declared `string`
 * makes no claim about the form of the value. Where the package does make one —
 * an EIN is nine digits, a timestamp is `M/D/YYYY h:mm:ss AM` — the contract
 * names that token instead, and a value that stops matching it fails even though
 * it is still, technically, a string. That is the point: a timestamp that turns
 * ISO breaks every caller parsing it, and the declared type never notices.
 */
export function permits(allowed, token) {
  const tokens = allowed.split('|');

  return tokens.includes(token) || (tokens.includes('string') && isStringToken(token));
}

/**
 * The flat expected signature for one endpoint, built from the shared parts.
 *
 * The record is described once and used for both endpoints, so single and bulk
 * cannot drift apart in the contract the way they can on the wire — where
 * `bmf_status` arrives as a string from one and a boolean from the other. One
 * description means one of those two has to be reported as wrong.
 */
export function composeExpected(contract, kind) {
  const single = kind === 'single';
  const prefix = single ? 'data.' : 'data[].';

  const expected = {
    ...contract.envelope,
    data: single ? 'null|object' : 'array|null',
    'errors[]': 'object',
    'errors[].eins[]': 'string',
  };

  for (const [field, token] of Object.entries(contract.errorDetail)) {
    expected[`errors[].${field}`] = token;
  }

  if (!single) {
    expected['data[]'] = 'object';
  }

  for (const [field, token] of Object.entries(contract.nonprofit)) {
    expected[`${prefix}${field}`] = token;
  }

  expected[`${prefix}organization_types[]`] = 'object';

  for (const [field, token] of Object.entries(contract.organizationType)) {
    expected[`${prefix}organization_types[].${field}`] = token;
  }

  return Object.fromEntries(
    Object.entries(expected).sort(([left], [right]) => (left < right ? -1 : left > right ? 1 : 0)),
  );
}

/**
 * Paths the live response carries a value the contract permits no form of.
 *
 * Paths the contract has never heard of are {@link coverageDiff}'s to report, so
 * a field the API invented is one failure rather than two.
 */
export function contractDiff(expected, observed) {
  const changes = [];

  for (const [path, token] of Object.entries(observed)) {
    const allowed = expected[path];

    if (allowed === undefined) {
      continue;
    }

    const offending = token.split('|').filter(one => !permits(allowed, one));

    if (offending.length > 0) {
      changes.push({ kind: 'changed', path, from: allowed, to: offending.join('|') });
    }
  }

  return { changes: sortChanges(changes), total: changes.length };
}

/**
 * Fields the API sent that the package does not predict.
 *
 * The index signature on `Nonprofit` means these are readable by a caller who
 * knows to look, and invisible to one who does not — which is the state this
 * check exists to end. An unpredicted field is a prediction gone stale, not a
 * broken response, so it is reported on its own.
 *
 * The reverse — a path the contract predicts and the response omitted — is not
 * a change. Every declared field is optional, and a record simply having no OFAC
 * finding is not the API moving. Only the count of those is surfaced.
 */
export function coverageDiff(expected, observed) {
  const changes = [];

  for (const [path, token] of Object.entries(observed)) {
    if (!Object.hasOwn(expected, path)) {
      changes.push({ kind: 'added', path, token });
    }
  }

  return {
    changes: sortChanges(changes),
    total: changes.length,
    unobserved: Object.keys(expected).filter(path => !Object.hasOwn(observed, path)).length,
  };
}
