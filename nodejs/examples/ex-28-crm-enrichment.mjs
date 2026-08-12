/**
 * EX-28 — Nonprofit CRM enrichment or synchronization.
 *
 * Uses a verified EIN as the stable key to refresh a CRM record with canonical
 * name, AKA, address, status, classification, profile URL and last-modified
 * metadata.
 *
 * The rule that makes this safe to run on a schedule: a `null` from the API is
 * an absence of data, not an instruction to erase. A sync that overwrites a
 * good, human-entered address with `null` because one IRS field was empty is a
 * data-loss bug that looks like a feature until someone notices.
 *
 * Run:  PACTMAN_API_KEY=... node examples/ex-28-crm-enrichment.mjs
 */
import { FIXTURE_EINS, withFixtureApi } from './lib/fixture-api.mjs';
import { bullet, field, heading, note, render } from './lib/print.mjs';

/** Fields this CRM keeps in sync, mapped to their source on the response. */
const SYNCED_FIELDS = [
  'organization_name',
  'organization_name_aka',
  'address_line1',
  'address_line2',
  'city',
  'state',
  'state_name',
  'zip',
  'subsection_description',
  'foundation_type_description',
  'bmf_status',
  'pub78_verified',
  'pactman_org_url',
  'organization_info_last_modified',
];

/** Existing CRM rows, keyed by EIN. Some hold better data than the API returns. */
const crm = new Map([
  [
    FIXTURE_EINS.publicCharity,
    {
      ein: FIXTURE_EINS.publicCharity,
      organization_name: 'Meals Today',
      organization_name_aka: null,
      address_line1: '50 Lowell Ave',
      address_line2: 'Suite 3B',
      city: 'Westfield',
      state: 'MA',
      state_name: 'Massachusetts',
      zip: '01085-2643',
      subsection_description: null,
      foundation_type_description: null,
      bmf_status: null,
      pub78_verified: null,
      pactman_org_url: null,
      organization_info_last_modified: null,
      verifiedAt: null,
    },
  ],
  [
    FIXTURE_EINS.sparseIdentity,
    {
      ein: FIXTURE_EINS.sparseIdentity,
      organization_name: 'Quiet Harbor Trust',
      organization_name_aka: 'QHT',
      address_line1: 'PO Box 118',
      address_line2: null,
      // Entered by a fundraiser who spoke to the organization. The API returns
      // null for these; that must not wipe them.
      city: 'Rockport',
      state: 'ME',
      state_name: 'Maine',
      zip: '04856',
      subsection_description: null,
      foundation_type_description: null,
      bmf_status: null,
      pub78_verified: null,
      pactman_org_url: null,
      organization_info_last_modified: null,
      verifiedAt: '2026-01-04T09:12:00.000Z',
    },
  ],
]);

/**
 * Merges a response into a CRM row.
 *
 * A field is written only when the API returned a usable value. `null` and
 * absent both mean "no update available" — never "clear this".
 */
function merge(record, nonprofit) {
  const updates = [];
  const skipped = [];
  const next = { ...record };

  for (const key of SYNCED_FIELDS) {
    const incoming = nonprofit[key];

    if (incoming === null || incoming === undefined) {
      skipped.push({ key, reason: incoming === null ? 'API returned null' : 'API returned no field' });
      continue;
    }

    if (record[key] === incoming) {
      continue;
    }

    updates.push({ key, before: record[key], after: incoming });
    next[key] = incoming;
  }

  return { next, updates, skipped };
}

await withFixtureApi(async client => {
  const eins = [...crm.keys()];
  const result = await client.nonprofits.checkBulk(eins);

  // EIN is the join key: stable, returned on every record, and the same value
  // your CRM already stores. Names change; EINs do not.
  const byEin = new Map(result.organizations.map(org => [org.ein, org]));

  for (const ein of eins) {
    const record = crm.get(ein);
    const nonprofit = byEin.get(ein);

    heading(`CRM record ${ein}`);

    if (!nonprofit) {
      // No record came back. Leave the row untouched and mark the attempt.
      field('sync', 'skipped — no record returned');
      bullet('The existing CRM data is retained; a failed lookup is not new information.');
      crm.set(ein, { ...record, lastSyncAttemptAt: new Date().toISOString() });
      continue;
    }

    const { next, updates, skipped } = merge(record, nonprofit);

    // A verification timestamp, so downstream code can tell fresh rows from
    // rows nobody has touched since import.
    next.verifiedAt = new Date().toISOString();
    next.verificationRequestId = result.requestId;
    next.verificationReportDate = nonprofit.report_date;

    crm.set(ein, next);

    field('fields updated', updates.length);

    for (const update of updates) {
      bullet(`${update.key}: ${render(update.before)} → ${render(update.after)}`);
    }

    field('fields left alone', skipped.length);

    for (const skip of skipped) {
      bullet(`${skip.key}: kept ${render(record[skip.key])} (${skip.reason})`);
    }

    field('verifiedAt', next.verifiedAt);
    field('previous verifiedAt', record.verifiedAt);
  }

  heading('CRM after synchronization');

  for (const [ein, record] of crm) {
    console.log(`  ${ein}  ${record.organization_name}`);
    console.log(
      `    aka=${render(record.organization_name_aka)}  city=${render(record.city)}` +
        `  zip=${render(record.zip)}  bmf=${render(record.bmf_status)}`,
    );
    console.log(`    profile=${render(record.pactman_org_url)}`);
    console.log(`    verifiedAt=${render(record.verifiedAt)}`);
  }
});

note(
  'Storing `verifiedAt` is what makes this data auditable. Without it, a row that\n' +
    'was checked yesterday and a row imported from a spreadsheet in 2019 look\n' +
    'identical — and only one of them is evidence.',
);
