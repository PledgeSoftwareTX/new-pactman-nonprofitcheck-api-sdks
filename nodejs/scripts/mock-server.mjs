/**
 * A tiny stand-in for the Nonprofit Check Plus API, so the examples can be run
 * in CI without a real key or network access.
 *
 * Only the two check endpoints are implemented, with the same envelope shape,
 * auth header and batch limit as the real service.
 */
import { createServer } from 'node:http';

const VALID_KEY = process.env.MOCK_API_KEY ?? 'mock-key';
const MAX_BULK_EINS = 50;
const KNOWN_EINS = new Set(['411787097', '996589560']);

function organization(ein) {
  return {
    pactman_org_url: `https://pactman.org/profile/nonprofit/example-${ein}`,
    organization_info_last_modified: '2/22/2026 1:16:30 AM',
    ein,
    organization_name: `EXAMPLE NONPROFIT ${ein.slice(-4)}`,
    city: 'WESTFIELD',
    state: 'MA',
    pub78_organization_name: `Example Nonprofit ${ein.slice(-4)}`,
    pub78_ein: ein,
    pub78_verified: true,
    most_recent_pub78: '12/12/2025 12:00:00 AM',
    bmf_ein: ein,
    bmf_status: true,
    bmf_subsection: '03',
    subsection_description: '501(c)(3) Public Charity',
    most_recent_bmf: '12/09/2025 12:00:00 AM',
    ofac_status:
      'This organization was NOT included in the Office of Foreign Assets Control Specially Designated Nationals (SDN) list.',
    ofac_list_published_date: '3/01/2026 12:00:00 AM',
    revocation_code: null,
    revocation_date: null,
    reinstatement_date: null,
    irs_bmf_pub78_conflict: false,
  };
}

function send(res, status, body) {
  const payload = JSON.stringify(body);
  res.writeHead(status, {
    'content-type': 'application/json',
    'x-request-id': `mock-${Date.now()}`,
  });
  res.end(payload);
}

function envelope(data, errors = null, checkCount = 1) {
  return { code: 200, message: 'OK', errors, data, timeTaken: 2, nonprofit_check_count: checkCount };
}

async function readJson(req) {
  const chunks = [];

  for await (const chunk of req) {
    chunks.push(chunk);
  }

  return JSON.parse(Buffer.concat(chunks).toString('utf8'));
}

export function startMockServer(port = 0) {
  const server = createServer(async (req, res) => {
    if (req.headers.authorization !== `Bearer ${VALID_KEY}`) {
      return send(res, 401, {
        code: 401,
        message: 'Unauthorized',
        errors: [{ resource: 'nonprofitcheck', reason: 'Invalid API Key' }],
        data: null,
      });
    }

    const url = new URL(req.url ?? '/', 'http://localhost');
    const single = url.pathname.match(/^\/api\/entities\/nonprofitcheck\/v1\/us\/ein\/(\d{9})$/);

    if (req.method === 'GET' && single) {
      const ein = single[1];

      return KNOWN_EINS.has(ein)
        ? send(res, 200, envelope(organization(ein)))
        : send(res, 404, {
            code: 404,
            message: 'Not Found',
            errors: [
              {
                resource: 'nonprofitcheck',
                reason: 'A nonprofit with this EIN does not exist in our records',
              },
            ],
            data: null,
          });
    }

    if (req.method === 'POST' && url.pathname === '/api/entities/nonprofitcheckbulk/v1/us/eins') {
      const eins = await readJson(req);

      if (!Array.isArray(eins)) {
        return send(res, 400, { code: 400, message: 'Bad Request', errors: null, data: null });
      }

      if (eins.length > MAX_BULK_EINS) {
        return send(res, 400, {
          code: 400,
          message: 'Bad Request',
          errors: [
            {
              resource: 'nonprofitcheckbulk',
              reason: `A maximum of ${MAX_BULK_EINS} EINs can be supplied to the nonprofit check bulk API`,
            },
          ],
          data: null,
        });
      }

      const matched = eins.filter(ein => KNOWN_EINS.has(ein));
      const missing = eins.filter(ein => !KNOWN_EINS.has(ein));
      const errors =
        missing.length === 0
          ? null
          : [
              {
                resource: 'nonprofitcheckbulk',
                reason: 'There are no matching nonprofits in our records for this set of EINs',
                code: 404,
                eins: missing,
              },
            ];

      return send(res, 200, envelope(matched.map(organization), errors, matched.length));
    }

    return send(res, 404, { code: 404, message: 'Not Found', errors: null, data: null });
  });

  return new Promise(resolve => {
    server.listen(port, '127.0.0.1', () => {
      const address = server.address();
      resolve({ server, url: `http://127.0.0.1:${address.port}` });
    });
  });
}

// Allow running standalone: `node scripts/mock-server.mjs 4010`
if (import.meta.url === `file://${process.argv[1]}`) {
  const { url } = await startMockServer(Number(process.argv[2] ?? 4010));
  console.log(`Mock Pactman API listening on ${url}`);
}
