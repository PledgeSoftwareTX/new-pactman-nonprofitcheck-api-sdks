/**
 * Structural validation of the address an API response carries.
 *
 * None of this is part of the SDK, and deliberately so. The API reports the
 * address IRS records hold; deciding whether that address is good enough to act
 * on is a customer policy question.
 *
 * What this answers: is the returned address *well-formed and self-consistent* —
 * are the components that matter present, is `state` a real USPS code, does
 * `state_name` agree with it, is `zip` shaped like a ZIP and does it belong to
 * the state claimed alongside it.
 *
 * What this does not answer: whether mail sent there arrives. Deliverability is
 * a question for USPS, Lob, Smarty or Google Address Validation, and it needs a
 * network call and a second credential. See {@link validateAddress} for where a
 * deliverability verdict would slot in.
 *
 * Every check is conservative in the same direction: a check that cannot be run
 * reports `not_checkable`, never `fail`. An incomplete lookup table here must
 * not manufacture a finding about somebody's address.
 */

/** USPS codes and the state names the API pairs them with. */
const US_STATES = new Map([
  ['AL', 'Alabama'], ['AK', 'Alaska'], ['AZ', 'Arizona'], ['AR', 'Arkansas'],
  ['CA', 'California'], ['CO', 'Colorado'], ['CT', 'Connecticut'], ['DE', 'Delaware'],
  ['DC', 'District of Columbia'], ['FL', 'Florida'], ['GA', 'Georgia'], ['HI', 'Hawaii'],
  ['ID', 'Idaho'], ['IL', 'Illinois'], ['IN', 'Indiana'], ['IA', 'Iowa'],
  ['KS', 'Kansas'], ['KY', 'Kentucky'], ['LA', 'Louisiana'], ['ME', 'Maine'],
  ['MD', 'Maryland'], ['MA', 'Massachusetts'], ['MI', 'Michigan'], ['MN', 'Minnesota'],
  ['MS', 'Mississippi'], ['MO', 'Missouri'], ['MT', 'Montana'], ['NE', 'Nebraska'],
  ['NV', 'Nevada'], ['NH', 'New Hampshire'], ['NJ', 'New Jersey'], ['NM', 'New Mexico'],
  ['NY', 'New York'], ['NC', 'North Carolina'], ['ND', 'North Dakota'], ['OH', 'Ohio'],
  ['OK', 'Oklahoma'], ['OR', 'Oregon'], ['PA', 'Pennsylvania'], ['RI', 'Rhode Island'],
  ['SC', 'South Carolina'], ['SD', 'South Dakota'], ['TN', 'Tennessee'], ['TX', 'Texas'],
  ['UT', 'Utah'], ['VT', 'Vermont'], ['VA', 'Virginia'], ['WA', 'Washington'],
  ['WV', 'West Virginia'], ['WI', 'Wisconsin'], ['WY', 'Wyoming'],
  // Territories and military posts. An exempt organization can hold any of these.
  ['AS', 'American Samoa'], ['GU', 'Guam'], ['MP', 'Northern Mariana Islands'],
  ['PR', 'Puerto Rico'], ['VI', 'Virgin Islands'],
  ['AA', 'Armed Forces Americas'], ['AE', 'Armed Forces Europe'], ['AP', 'Armed Forces Pacific'],
]);

/**
 * Leading three ZIP digits each state uses, as inclusive ranges.
 *
 * Illustrative, not the USPS product. A prefix this table does not list makes
 * the ZIP-to-state check `not_checkable`, so omissions cost coverage rather
 * than producing a false finding. Prefixes claimed by more than one state —
 * 06390 on Fishers Island is New York inside Connecticut's range, 340 is a
 * military post inside Florida's — pass for any of their claimants.
 */
const ZIP_PREFIXES = new Map([
  ['AL', [[350, 369]]], ['AK', [[995, 999]]], ['AZ', [[850, 865]]], ['AR', [[716, 729]]],
  ['CA', [[900, 961]]], ['CO', [[800, 816]]], ['CT', [[60, 69]]], ['DE', [[197, 199]]],
  ['DC', [[200, 200], [202, 205], [569, 569]]], ['FL', [[320, 349]]],
  ['GA', [[300, 319], [398, 399]]], ['HI', [[967, 968]]], ['ID', [[832, 838]]],
  ['IL', [[600, 629]]], ['IN', [[460, 479]]], ['IA', [[500, 528]]], ['KS', [[660, 679]]],
  ['KY', [[400, 427]]], ['LA', [[700, 714]]], ['ME', [[39, 49]]], ['MD', [[206, 219]]],
  ['MA', [[10, 27], [55, 55]]], ['MI', [[480, 499]]], ['MN', [[550, 567]]],
  ['MS', [[386, 397]]], ['MO', [[630, 658]]], ['MT', [[590, 599]]], ['NE', [[680, 693]]],
  ['NV', [[889, 898]]], ['NH', [[30, 38]]], ['NJ', [[70, 89]]], ['NM', [[870, 884]]],
  ['NY', [[5, 5], [63, 63], [100, 149]]], ['NC', [[270, 289]]], ['ND', [[580, 588]]],
  ['OH', [[430, 459]]], ['OK', [[730, 731], [734, 749]]], ['OR', [[970, 979]]],
  ['PA', [[150, 196]]],
  ['RI', [[28, 29]]], ['SC', [[290, 299]]], ['SD', [[570, 577]]], ['TN', [[370, 385]]],
  // 733 is Austin, inside Oklahoma's run — the IRS's own service centre sits there.
  ['TX', [[733, 733], [750, 799], [885, 885]]], ['UT', [[840, 847]]], ['VT', [[50, 59]]],
  ['VA', [[201, 201], [220, 246]]], ['WA', [[980, 994]]], ['WV', [[247, 268]]],
  ['WI', [[530, 549]]], ['WY', [[820, 831]]],
  ['AS', [[967, 967]]], ['GU', [[969, 969]]], ['MP', [[969, 969]]], ['PR', [[6, 9]]],
  ['VI', [[8, 8]]], ['AA', [[340, 340]]], ['AE', [[90, 98]]], ['AP', [[962, 966]]],
]);

/** Prefix → every state that claims it, built once from the ranges above. */
const PREFIX_OWNERS = (() => {
  const owners = new Map();

  for (const [state, ranges] of ZIP_PREFIXES) {
    for (const [low, high] of ranges) {
      for (let prefix = low; prefix <= high; prefix += 1) {
        const claimants = owners.get(prefix) ?? new Set();

        claimants.add(state);
        owners.set(prefix, claimants);
      }
    }
  }

  return owners;
})();

/**
 * Values that occupy a field without saying anything.
 *
 * These arrive in real IRS extracts. Left unchecked they read as data: a `city`
 * of `UNKNOWN` is present, is a string, and is not null.
 */
const PLACEHOLDERS = new Set([
  'N/A', 'NA', 'N A', 'NONE', 'NULL', 'NIL', 'UNKNOWN', 'UNK', 'TBD',
  'NOT AVAILABLE', 'NOT APPLICABLE', 'NO ADDRESS', 'SAME', 'SEE ATTACHED',
  '-', '--', '.', '...', 'X', 'XX', 'XXX', 'XXXX', '0', '00', '000',
]);

/** Street lines that legitimately carry no house number. */
const NUMBERLESS_LINES = new Set(['GENERAL DELIVERY', 'PO BOX', 'POST OFFICE BOX']);

/** Components an address needs before it locates anything. */
export const REQUIRED_COMPONENTS = ['address_line1', 'city', 'state', 'zip'];

/** Every component this module looks at, required or not. */
export const ADDRESS_COMPONENTS = [
  'address_line1',
  'address_line2',
  'city',
  'state',
  'state_name',
  'zip',
];

function isAbsent(value) {
  return value === null || value === undefined || String(value).trim() === '';
}

function squash(value) {
  return String(value).toUpperCase().replace(/[^A-Z0-9]+/g, ' ').trim();
}

/** True when a value is present but carries no information. */
export function isPlaceholder(value) {
  if (isAbsent(value)) {
    return false;
  }

  const text = String(value).trim().toUpperCase();

  return PLACEHOLDERS.has(text) || PLACEHOLDERS.has(squash(text));
}

/** The five-digit prefix of a ZIP, or `null` when there is nothing to read. */
export function zip5(value) {
  if (isAbsent(value)) {
    return null;
  }

  const digits = String(value).replace(/\D/g, '');

  return digits.length >= 5 ? digits.slice(0, 5) : null;
}

/** `ME` for `04856`, `null` when no state claims the prefix. Set for shared ones. */
export function statesForZip(value) {
  const five = zip5(value);

  if (five === null) {
    return null;
  }

  return PREFIX_OWNERS.get(Number(five.slice(0, 3))) ?? null;
}

function check(id, label, outcome, detail) {
  return { id, label, outcome, detail };
}

/**
 * Runs every structural check against one returned address.
 *
 * @param record  Anything carrying the six address fields — a `nonprofit` from
 *                `client.nonprofits.check()` reads directly.
 * @returns `{ verdict, checks, missing, failures }`. `verdict` is `inconsistent`
 *          when a check failed, `incomplete` when a required component was not
 *          returned, and `usable` when neither happened. It is never
 *          `deliverable`: nothing here has asked USPS anything.
 */
export function validateAddress(record) {
  const value = component => record?.[component];
  const checks = [];

  // 1. Presence. A component the API did not return has not been confirmed by
  //    anything, which is the same lesson the comparison examples teach.
  const missing = REQUIRED_COMPONENTS.filter(component => isAbsent(value(component)));

  checks.push(
    missing.length === 0
      ? check('required_components', 'required components present', 'pass', REQUIRED_COMPONENTS.join(', '))
      : check('required_components', 'required components present', 'fail', `not returned: ${missing.join(', ')}`),
  );

  // 2. Placeholders. Present, and still empty of meaning.
  const placeholders = ADDRESS_COMPONENTS.filter(component => isPlaceholder(value(component)));

  checks.push(
    placeholders.length === 0
      ? check('no_placeholders', 'no placeholder values', 'pass', null)
      : check(
          'no_placeholders',
          'no placeholder values',
          'fail',
          placeholders.map(component => `${component}="${value(component)}"`).join(', '),
        ),
  );

  // 3. The state code itself.
  const state = isAbsent(value('state')) ? null : String(value('state')).trim().toUpperCase();

  checks.push(
    state === null
      ? check('state_code', 'state is a USPS code', 'not_checkable', 'state was not returned')
      : US_STATES.has(state)
        ? check('state_code', 'state is a USPS code', 'pass', `${state} — ${US_STATES.get(state)}`)
        : check('state_code', 'state is a USPS code', 'fail', `"${value('state')}" is not a USPS code`),
  );

  // 4. state_name against state. Two fields for one fact is two chances to be
  //    wrong, and IRS extracts do disagree with themselves.
  const stateName = isAbsent(value('state_name')) ? null : String(value('state_name')).trim();
  const expectedName = state === null ? null : US_STATES.get(state);

  checks.push(
    stateName === null || expectedName === undefined || expectedName === null
      ? check('state_name_agrees', 'state_name agrees with state', 'not_checkable', stateName === null ? 'state_name was not returned' : 'state is not a known code')
      : squash(stateName) === squash(expectedName)
        ? check('state_name_agrees', 'state_name agrees with state', 'pass', stateName)
        : check(
            'state_name_agrees',
            'state_name agrees with state',
            'fail',
            `state=${state} implies "${expectedName}", state_name says "${stateName}"`,
          ),
  );

  // 5. ZIP shape. Five digits, or nine for ZIP+4. Anything else is not a ZIP.
  const rawZip = isAbsent(value('zip')) ? null : String(value('zip')).trim();
  const zipDigits = rawZip === null ? '' : rawZip.replace(/\D/g, '');

  checks.push(
    rawZip === null
      ? check('zip_format', 'zip is 5 or 9 digits', 'not_checkable', 'zip was not returned')
      : zipDigits.length === 5 || zipDigits.length === 9
        ? check('zip_format', 'zip is 5 or 9 digits', 'pass', rawZip)
        : check('zip_format', 'zip is 5 or 9 digits', 'fail', `"${rawZip}" has ${zipDigits.length} digits`),
  );

  // 6. ZIP against state. The check that catches a transcription error no
  //    single-field check can see.
  const claimants = statesForZip(rawZip);

  checks.push(
    rawZip === null || state === null
      ? check('zip_matches_state', 'zip belongs to state', 'not_checkable', 'zip or state was not returned')
      : claimants === null
        ? check('zip_matches_state', 'zip belongs to state', 'not_checkable', `no state is on file for prefix ${zip5(rawZip)?.slice(0, 3) ?? '???'}`)
        : claimants.has(state)
          ? check('zip_matches_state', 'zip belongs to state', 'pass', `${zip5(rawZip)} is a ${state} ZIP`)
          : check(
              'zip_matches_state',
              'zip belongs to state',
              'fail',
              `${zip5(rawZip)} belongs to ${[...claimants].join('/')}, state says ${state}`,
            ),
  );

  // 7. The street line. A number, a box, or general delivery.
  const line1 = isAbsent(value('address_line1')) ? null : squash(value('address_line1'));

  checks.push(
    line1 === null
      ? check('line1_shape', 'address_line1 locates a delivery point', 'not_checkable', 'address_line1 was not returned')
      : /\d/.test(line1) || NUMBERLESS_LINES.has(line1)
        ? check('line1_shape', 'address_line1 locates a delivery point', 'pass', value('address_line1'))
        : check(
            'line1_shape',
            'address_line1 locates a delivery point',
            'fail',
            `"${value('address_line1')}" carries no number, box or general-delivery marker`,
          ),
  );

  const failures = checks.filter(entry => entry.outcome === 'fail');

  // A deliverability verdict from USPS or an equivalent would be folded in
  // here, as one more check. Nothing above has left the process.
  const verdict = failures.some(entry => entry.id !== 'required_components')
    ? 'inconsistent'
    : missing.length > 0
      ? 'incomplete'
      : 'usable';

  return { verdict, checks, missing, failures };
}

/** True for the one verdict that clears an address for automated use. */
export function isUsable(verdict) {
  return verdict === 'usable';
}
