import { describe, expect, it } from 'vitest';
import { PactmanClient } from '../src/client.js';
import { PactmanValidationError } from '../src/errors.js';
import { MAX_BULK_EINS } from '../src/environments.js';
import { PACKAGE_NAME } from '../src/version.js';
import { createFetchMock, envelope, nonprofitFixture, TEST_API_KEY } from './helpers.js';

const BASE_URL = 'http://mock.test';

function clientWith(mock: ReturnType<typeof createFetchMock>): PactmanClient {
  return new PactmanClient({ apiKey: TEST_API_KEY, baseUrl: BASE_URL, fetch: mock.fetch });
}

describe('nonprofits.check', () => {
  it('sends exactly one authenticated request and returns a deserialized model', async () => {
    const mock = createFetchMock([{ body: envelope(nonprofitFixture()) }]);
    const result = await clientWith(mock).nonprofits.check('411787097');

    expect(mock.requests).toHaveLength(1);

    const request = mock.requests[0];
    expect(request?.method).toBe('GET');
    expect(request?.url).toBe(`${BASE_URL}/api/entities/nonprofitcheck/v1/us/ein/411787097`);
    expect(request?.headers.get('authorization')).toBe(`Bearer ${TEST_API_KEY}`);
    expect(request?.headers.get('accept')).toBe('application/json');
    expect(request?.headers.get('user-agent')).toContain(
      PACKAGE_NAME.replace('@', '').replace('/', '-'),
    );

    expect(result.nonprofit?.organization_name).toBe('EXAMPLE NONPROFIT');
    expect(result.nonprofit?.ein).toBe('411787097');
  });

  it('normalizes a hyphenated EIN before building the URL', async () => {
    const mock = createFetchMock([{ body: envelope(nonprofitFixture()) }]);
    await clientWith(mock).nonprofits.check('41-1787097');

    expect(mock.requests[0]?.url).toMatch(/\/us\/ein\/411787097$/);
  });

  it('maps usage information from the envelope', async () => {
    const mock = createFetchMock([
      { body: envelope(nonprofitFixture(), { nonprofit_check_count: 7, timeTaken: 42 }) },
    ]);
    const result = await clientWith(mock).nonprofits.check('411787097');

    expect(result.checkCount).toBe(7);
    expect(result.timeTakenMs).toBe(42);
    expect(result.status).toBe(200);
  });

  it('exposes source findings and preserves null and false as distinct values', async () => {
    const mock = createFetchMock([
      {
        body: envelope(
          nonprofitFixture({
            pub78_verified: false,
            bmf_status: null,
            revocation_code: null,
            irs_bmf_pub78_conflict: false,
          }),
        ),
      },
    ]);
    const { nonprofit } = await clientWith(mock).nonprofits.check('411787097');

    expect(nonprofit?.pub78_verified).toBe(false);
    expect(nonprofit?.bmf_status).toBeNull();
    expect(nonprofit?.revocation_code).toBeNull();
    expect(nonprofit?.irs_bmf_pub78_conflict).toBe(false);
    expect(nonprofit?.ofac_status).toContain('NOT included');
  });

  it('keeps unknown future fields readable through the raw response', async () => {
    const mock = createFetchMock([
      {
        body: {
          ...envelope(nonprofitFixture({ future_source_status: 'listed' })),
          future_envelope_field: { nested: true },
        },
      },
    ]);
    const result = await clientWith(mock).nonprofits.check('411787097');

    expect(result.nonprofit?.organization_name).toBe('EXAMPLE NONPROFIT');
    expect(result.nonprofit?.['future_source_status']).toBe('listed');
    expect(result.raw['future_envelope_field']).toEqual({ nested: true });
  });

  it('returns null rather than throwing when data is absent', async () => {
    const mock = createFetchMock([{ body: envelope(null, { nonprofit_check_count: 0 }) }]);
    const result = await clientWith(mock).nonprofits.check('411787097');

    expect(result.nonprofit).toBeNull();
    expect(result.checkCount).toBe(0);
  });

  it('fails locally on a malformed EIN without sending a request', async () => {
    const mock = createFetchMock([{ body: envelope(nonprofitFixture()) }]);

    await expect(clientWith(mock).nonprofits.check('41178709')).rejects.toBeInstanceOf(
      PactmanValidationError,
    );
    expect(mock.requests).toHaveLength(0);
  });
});

describe('nonprofits.checkBulk', () => {
  it('sends one request with a bare JSON array of normalized EINs', async () => {
    const mock = createFetchMock([
      { body: envelope([nonprofitFixture(), nonprofitFixture({ ein: '996589560' })]) },
    ]);
    const result = await clientWith(mock).nonprofits.checkBulk(['41-1787097', '996589560']);

    expect(mock.requests).toHaveLength(1);

    const request = mock.requests[0];
    expect(request?.method).toBe('POST');
    expect(request?.url).toBe(`${BASE_URL}/api/entities/nonprofitcheckbulk/v1/us/eins`);
    expect(request?.headers.get('content-type')).toBe('application/json');
    expect(JSON.parse(request?.body ?? 'null')).toEqual(['411787097', '996589560']);

    expect(result.organizations).toHaveLength(2);
    expect(result.organizations[1]?.ein).toBe('996589560');
  });

  it('preserves input order and duplicates by default', async () => {
    const mock = createFetchMock([{ body: envelope([]) }]);
    await clientWith(mock).nonprofits.checkBulk(['996589560', '41-1787097', '996589560']);

    expect(JSON.parse(mock.requests[0]?.body ?? 'null')).toEqual([
      '996589560',
      '411787097',
      '996589560',
    ]);
  });

  it('removes duplicates only when dedupe is requested', async () => {
    const mock = createFetchMock([{ body: envelope([]) }]);
    await clientWith(mock).nonprofits.checkBulk(['996589560', '996589560', '41-1787097'], {
      dedupe: true,
    });

    expect(JSON.parse(mock.requests[0]?.body ?? 'null')).toEqual(['996589560', '411787097']);
  });

  it('rejects an empty collection locally', async () => {
    const mock = createFetchMock([{ body: envelope([]) }]);

    await expect(clientWith(mock).nonprofits.checkBulk([])).rejects.toBeInstanceOf(
      PactmanValidationError,
    );
    expect(mock.requests).toHaveLength(0);
  });

  it('rejects the whole batch when one EIN is malformed, before sending', async () => {
    const mock = createFetchMock([{ body: envelope([]) }]);

    await expect(
      clientWith(mock).nonprofits.checkBulk(['411787097', 'not-an-ein']),
    ).rejects.toBeInstanceOf(PactmanValidationError);
    expect(mock.requests).toHaveLength(0);
  });

  it('enforces the server batch limit locally, from a single constant', async () => {
    const mock = createFetchMock([{ body: envelope([]) }]);
    const tooMany = Array.from({ length: MAX_BULK_EINS + 1 }, () => '411787097');

    await expect(clientWith(mock).nonprofits.checkBulk(tooMany)).rejects.toThrowError(
      new RegExp(`at most ${MAX_BULK_EINS} EINs`),
    );
    expect(mock.requests).toHaveLength(0);
  });

  it('accepts exactly the batch limit', async () => {
    const mock = createFetchMock([{ body: envelope([]) }]);
    const atLimit = Array.from({ length: MAX_BULK_EINS }, () => '411787097');

    await clientWith(mock).nonprofits.checkBulk(atLimit);

    expect(mock.requests).toHaveLength(1);
  });

  it('surfaces per-item not-found results from a successful response', async () => {
    const mock = createFetchMock([
      {
        status: 200,
        body: envelope([nonprofitFixture()], {
          nonprofit_check_count: 1,
          errors: [
            {
              resource: 'nonprofitcheckbulk',
              reason: 'There are no matching nonprofits in our records for this set of EINs',
              code: 404,
              eins: ['996589560'],
            },
          ],
        }),
      },
    ]);
    const result = await clientWith(mock).nonprofits.checkBulk(['411787097', '996589560']);

    expect(result.organizations).toHaveLength(1);
    expect(result.notFoundEins).toEqual(['996589560']);
    expect(result.errors[0]?.code).toBe(404);
    expect(result.checkCount).toBe(1);
  });

  it('reads organizations from a wrapped data object as well as a bare array', async () => {
    const mock = createFetchMock([
      { body: envelope({ organizations: [nonprofitFixture()] }) },
    ]);
    const result = await clientWith(mock).nonprofits.checkBulk(['411787097']);

    expect(result.organizations).toHaveLength(1);
  });

  it('rejects a non-array input locally', async () => {
    const mock = createFetchMock([{ body: envelope([]) }]);
    const notAnArray = '411787097' as unknown as string[];

    await expect(clientWith(mock).nonprofits.checkBulk(notAnArray)).rejects.toBeInstanceOf(
      PactmanValidationError,
    );
    expect(mock.requests).toHaveLength(0);
  });
});
