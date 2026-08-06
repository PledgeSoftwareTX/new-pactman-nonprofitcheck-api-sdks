import type { FetchLike } from '../src/config.js';
import type { TransportHooks } from '../src/http.js';
import type { ApiEnvelope, Nonprofit } from '../src/types.js';

/** A canned HTTP response, or an error the transport should see thrown. */
export interface StubResponse {
  status?: number;
  body?: unknown;
  bodyText?: string;
  headers?: Record<string, string>;
}

export type Stub = StubResponse | Error;

export interface RecordedRequest {
  url: string;
  method: string;
  headers: Headers;
  body: string | undefined;
}

export interface FetchMock {
  fetch: FetchLike;
  requests: RecordedRequest[];
}

/**
 * Serves `stubs` in order; the last one repeats once the queue is exhausted so
 * a retry test can end on a stable outcome.
 */
export function createFetchMock(stubs: Stub[]): FetchMock {
  const requests: RecordedRequest[] = [];
  let index = 0;

  const fetch: FetchLike = async (url, init) => {
    requests.push({
      url,
      method: init.method ?? 'GET',
      headers: new Headers(init.headers as HeadersInit | undefined),
      body: typeof init.body === 'string' ? init.body : undefined,
    });

    const stub = stubs[Math.min(index, stubs.length - 1)];
    index += 1;

    if (stub === undefined) {
      throw new Error('createFetchMock was called with an empty stub list.');
    }

    if (stub instanceof Error) {
      throw stub;
    }

    const headers = new Headers(stub.headers ?? {});

    if (!headers.has('content-type')) {
      headers.set('content-type', 'application/json');
    }

    const payload = stub.bodyText ?? (stub.body === undefined ? '' : JSON.stringify(stub.body));

    return new Response(payload === '' ? null : payload, {
      status: stub.status ?? 200,
      headers,
    });
  };

  return { fetch, requests };
}

/** Records requested delays instead of waiting, so retry tests stay instant. */
export interface ClockMock extends TransportHooks {
  delays: number[];
}

export function createClock(random = 1): ClockMock {
  const delays: number[] = [];

  return {
    delays,
    sleep: async (ms: number, signal?: AbortSignal) => {
      if (signal?.aborted) {
        throw new Error('aborted while sleeping');
      }

      delays.push(ms);
    },
    random: () => random,
  };
}

/** A representative organization, mirroring the published response example. */
export function nonprofitFixture(overrides: Partial<Nonprofit> = {}): Nonprofit {
  return {
    pactman_org_url: 'https://pactman.org/profile/nonprofit/example-nonprofit-r5U9r8yRcZ',
    organization_info_last_modified: '2/22/2026 1:16:30 AM',
    ein: '411787097',
    organization_name: 'EXAMPLE NONPROFIT',
    organization_name_aka: 'EXAMPLE N.P',
    address_line1: '50 LOWELL AVE',
    address_line2: 'APT 3B',
    city: 'WESTFIELD',
    state: 'MA',
    state_name: 'Massachusetts',
    zip: '01085-2643',
    filing_req_code: '00',
    pub78_church_message: null,
    pub78_organization_name: 'Example Nonprofit',
    pub78_ein: '411787097',
    pub78_verified: true,
    pub78_city: 'Westfield',
    pub78_state: 'MA',
    pub78_indicator: '0',
    organization_types: [
      {
        organization_type: 'Deductions for donations to public charities are generally limited...',
        deductibility_limitation: '50%',
        deductibility_status_description: 'PC',
      },
    ],
    most_recent_pub78: '12/12/2025 12:00:00 AM',
    bmf_church_message: null,
    bmf_organization_name: 'EXAMPLE NONPROFIT',
    bmf_ein: '411787097',
    bmf_status: true,
    most_recent_bmf: '12/09/2025 12:00:00 AM',
    bmf_subsection: '03',
    subsection_description: '501(c)(3) Public Charity',
    foundation_code: '10',
    foundation_code_description: 'Public charity described in section 509(a)(1) or (2)',
    ruling_month: '07',
    ruling_year: '2024',
    group_exemption: '0000',
    exempt_status_code: '01',
    ofac_status:
      'This organization was NOT included in the Office of Foreign Assets Control Specially Designated Nationals (SDN) list.',
    revocation_code: null,
    revocation_date: null,
    reinstatement_date: null,
    irs_bmf_pub78_conflict: false,
    foundation_509a_status: 'N/A',
    report_date: '3/25/2026 3:28:54 PM',
    foundation_type_code: 'pc',
    foundation_type_description: 'Public charity described in section 509(a)(1) or (2)',
    ...overrides,
  };
}

/** Wraps data in the envelope the API returns. */
export function envelope<TData>(
  data: TData,
  overrides: Partial<ApiEnvelope<TData>> = {},
): ApiEnvelope<TData> {
  return {
    code: 200,
    message: 'OK',
    errors: null,
    data,
    timeTaken: 3,
    nonprofit_check_count: 1,
    ...overrides,
  };
}

/** A key that must never appear in any diagnostic output. */
export const TEST_API_KEY = 'pactman_test_key_do_not_leak_8f2b';

/** Awaits a promise that must reject, and returns the error it rejected with. */
export async function captureError<TError>(promise: Promise<unknown>): Promise<TError> {
  try {
    await promise;
  } catch (error) {
    return error as TError;
  }

  throw new Error('Expected the call to reject, but it resolved.');
}
