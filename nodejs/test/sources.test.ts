import { describe, expect, it } from 'vitest';
import { getAroe, getBmf, getOfac, getPub78 } from '../src/sources.js';
import type { Nonprofit } from '../src/types.js';
import { nonprofitFixture } from './helpers.js';

describe('source projections', () => {
  it('maps Publication 78 fields from the response', () => {
    const pub78 = getPub78(nonprofitFixture());

    expect(pub78).not.toBeNull();
    expect(pub78?.verified).toBe(true);
    expect(pub78?.ein).toBe('411787097');
    expect(pub78?.organization_name).toBe('Example Nonprofit');
    expect(pub78?.most_recent).toBe('12/12/2025 12:00:00 AM');
    expect(pub78?.organization_types?.[0]?.deductibility_limitation).toBe('50%');
  });

  it('maps Business Master File fields from the response', () => {
    const bmf = getBmf(nonprofitFixture());

    expect(bmf?.status).toBe(true);
    expect(bmf?.subsection).toBe('03');
    expect(bmf?.subsection_description).toBe('501(c)(3) Public Charity');
    expect(bmf?.foundation_code_description).toBe(
      'Public charity described in section 509(a)(1) or (2)',
    );
    expect(bmf?.most_recent).toBe('12/09/2025 12:00:00 AM');
  });

  it('maps Automatic Revocation fields from the response', () => {
    const aroe = getAroe(
      nonprofitFixture({
        revocation_code: '01',
        revocation_date: '3/06/2026 9:41:03 PM',
        reinstatement_date: '3/07/2026 9:41:03 PM',
        aroe_list_published_date: '3/01/2026 12:00:00 AM',
      }),
    );

    expect(aroe?.revocation_code).toBe('01');
    expect(aroe?.reinstatement_date).toBe('3/07/2026 9:41:03 PM');
    expect(aroe?.list_published_date).toBe('3/01/2026 12:00:00 AM');
  });

  it('maps OFAC fields verbatim, without deriving a boolean', () => {
    const ofac = getOfac(nonprofitFixture());

    expect(ofac?.status).toContain('NOT included');
    expect(Object.keys(ofac ?? {})).toEqual(['status']);
    expect(ofac).not.toHaveProperty('has_match');
    expect(ofac).not.toHaveProperty('matched');
  });

  it('keeps a missing source distinct from an explicit negative', () => {
    const withoutOfac: Nonprofit = { ein: '411787097', organization_name: 'NO SOURCES' };
    const negativePub78 = nonprofitFixture({ pub78_verified: false });
    const nullPub78 = nonprofitFixture({
      pub78_verified: null,
      pub78_organization_name: null,
      pub78_ein: null,
      pub78_city: null,
      pub78_state: null,
      pub78_indicator: null,
      pub78_church_message: null,
      pub78_source_org_type_1: null,
      pub78_source_org_type_2: null,
      pub78_source_org_type_3: null,
      organization_types: null,
      most_recent_pub78: null,
    });

    expect(getOfac(withoutOfac)).toBeNull();
    expect(getPub78(withoutOfac)).toBeNull();

    expect(getPub78(negativePub78)).not.toBeNull();
    expect(getPub78(negativePub78)?.verified).toBe(false);

    expect(getPub78(nullPub78)).not.toBeNull();
    expect(getPub78(nullPub78)?.verified).toBeNull();
  });

  it('reports a source as present when only some of its fields were returned', () => {
    const partial: Nonprofit = { ein: '411787097', bmf_status: false };
    const bmf = getBmf(partial);

    expect(bmf).not.toBeNull();
    expect(bmf?.status).toBe(false);
    expect(bmf?.subsection).toBeUndefined();
  });

  it('never produces a composite verdict field', () => {
    const record = nonprofitFixture();
    const projected = {
      ...getPub78(record),
      ...getBmf(record),
      ...getAroe(record),
      ...getOfac(record),
    };

    for (const key of Object.keys(projected)) {
      expect(key).not.toMatch(/approved|eligible|safe|passed|verdict/i);
    }
  });
});
