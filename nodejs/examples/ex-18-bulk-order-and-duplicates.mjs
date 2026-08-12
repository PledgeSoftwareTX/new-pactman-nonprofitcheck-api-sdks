/**
 * EX-18 — Bulk input order and duplicate EINs.
 *
 * Three things worth knowing before you zip a bulk response against your input:
 *
 *   1. The SDK sends your EINs in the order you supplied them, duplicates
 *      included. It does not reorder and it does not deduplicate.
 *   2. The API matches by set membership. Response order is not guaranteed to
 *      follow request order, and a duplicated EIN comes back once. Index results
 *      by EIN; never pair them positionally.
 *   3. `nonprofit_check_count` is not the count of unique EINs you sent. Do not
 *      reconstruct usage from your input — read the number the API reports.
 *
 * Run:  PACTMAN_API_KEY=... node examples/ex-18-bulk-order-and-duplicates.mjs
 */
import { FIXTURE_EINS, withFixtureApi } from './lib/fixture-api.mjs';
import { bullet, field, heading, note } from './lib/print.mjs';

await withFixtureApi(async client => {
  // Deliberately unsorted, with one EIN repeated twice.
  const requested = [
    FIXTURE_EINS.publicCharitySecond,
    FIXTURE_EINS.publicCharity,
    FIXTURE_EINS.publicCharitySecond,
    FIXTURE_EINS.privateFoundation,
  ];

  heading('Sent as supplied — no reordering, no deduplication');
  requested.forEach((ein, index) => bullet(`[${index}] ${ein}`));
  field('unique EINs', new Set(requested).size);
  field('EINs sent', requested.length);

  const before = await client.nonprofits.check(FIXTURE_EINS.publicCharity);
  const result = await client.nonprofits.checkBulk(requested);

  heading('Returned');
  result.organizations.forEach((org, index) => bullet(`[${index}] ${org.ein}  ${org.organization_name}`));

  const returnedOrder = result.organizations.map(org => org.ein);
  const requestOrderUnique = [...new Set(requested)];

  field('response length', returnedOrder.length);
  field('request length', requested.length);
  field(
    'positional pairing valid',
    returnedOrder.length === requested.length &&
      returnedOrder.every((ein, index) => ein === requested[index]),
  );
  field(
    'matches request order (deduped)',
    returnedOrder.length === requestOrderUnique.length &&
      returnedOrder.every((ein, index) => ein === requestOrderUnique[index]),
  );

  // The correct way to consume a bulk response.
  const byEin = new Map(result.organizations.map(org => [org.ein, org]));

  heading('Indexed by EIN — the pairing that always holds');

  for (const [index, ein] of requested.entries()) {
    const org = byEin.get(ein);
    console.log(
      `  input[${index}] ${ein} → ${org ? org.organization_name : 'no record returned'}` +
        `${requested.indexOf(ein) !== index ? '   (duplicate of an earlier input)' : ''}`,
    );
  }

  heading('Usage is reported, not inferred');
  field('unique EINs submitted', new Set(requested).size);
  field('total EINs submitted', requested.length);
  field('organizations returned', result.organizations.length);
  field('checkCount before this call', before.checkCount);
  field('checkCount after this call', result.checkCount);
  field(
    'delta',
    before.checkCount !== null && result.checkCount !== null
      ? result.checkCount - before.checkCount
      : '<not reported>',
  );

  bullet('Each submitted EIN is billable, duplicates included.');
  bullet('The delta above is the authority on what this request consumed.');
  bullet('Deriving usage from your unique-input count will disagree with the invoice.');

  // Opt in when duplicates are an artifact of your data rather than intent.
  heading('Opting in to deduplication');

  const deduped = await client.nonprofits.checkBulk(requested, { dedupe: true });

  field('EINs sent after dedupe', new Set(requested).size);
  field('organizations returned', deduped.organizations.length);
  field('checkCount', deduped.checkCount);
  field(
    'delta',
    result.checkCount !== null && deduped.checkCount !== null
      ? deduped.checkCount - result.checkCount
      : '<not reported>',
  );
});

note(
  'Deduplication is off by default because collapsing a list silently would\n' +
    'misreport what was checked. Pass { dedupe: true } when you mean it.',
);
