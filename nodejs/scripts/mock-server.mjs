/**
 * A stand-in for the Nonprofit Check Plus API, so the examples can be run in CI
 * without a real key or network access.
 *
 * Only the two check endpoints are implemented, with the same envelope shape,
 * auth header, batch limit, bulk matching semantics and cumulative check count
 * as the real service. Records come from `fixtures.mjs`.
 */
import { createServer } from 'node:http';
import { CONTROL_EINS, FIXTURE_EINS, fixtureOrganization, hasFixture } from './fixtures.mjs';

const MAX_BULK_EINS = 50;
const SINGLE_PATH = /^\/api\/entities\/nonprofitcheck\/v1\/us\/ein\/(\d{9})$/;
const BULK_PATH = '/api/entities/nonprofitcheckbulk/v1/us/eins';

/** How long the `slow` control EIN holds a response open. */
const SLOW_RESPONSE_MS = 5_000;
/** How many times the `transientFailure` control EIN fails before succeeding. */
const TRANSIENT_FAILURES = 2;

function send(res, status, body, headers = {}) {
  res.writeHead(status, {
    'content-type': 'application/json',
    'x-request-id': `mock-${Math.random().toString(36).slice(2, 10)}`,
    ...headers,
  });
  res.end(JSON.stringify(body));
}

/** The success envelope. `nonprofit_check_count` is the billing-cycle total. */
function envelope(data, errors, checkCount) {
  return {
    code: 200,
    message: 'OK',
    errors: errors ?? null,
    data,
    timeTaken: 2 + Math.floor(Math.random() * 40),
    nonprofit_check_count: checkCount,
  };
}

function errorEnvelope(code, message, errors, checkCount) {
  return { code, message, errors, data: null, timeTaken: 1, nonprofit_check_count: checkCount };
}

async function readJson(req) {
  const chunks = [];

  for await (const chunk of req) {
    chunks.push(chunk);
  }

  const text = Buffer.concat(chunks).toString('utf8');

  return text.trim() === '' ? null : JSON.parse(text);
}

/**
 * Starts the mock API.
 *
 * @param options.port   0 picks a free port. A bare number is also accepted.
 * @param options.apiKey Key the server accepts. Defaults to `mock-key`.
 */
export function startMockServer(options = {}) {
  const port = typeof options === 'number' ? options : (options.port ?? 0);
  const validKey = options.apiKey ?? process.env.MOCK_API_KEY ?? 'mock-key';

  // Mirrors the real service: a running total for the billing cycle, not the
  // size of the current request.
  let checksUsedThisCycle = 0;
  let transientFailuresLeft = TRANSIENT_FAILURES;
  const pendingTimers = new Set();

  function handleSingle(res, ein) {
    if (ein === CONTROL_EINS.rateLimited) {
      return send(
        res,
        429,
        errorEnvelope(
          429,
          'Too Many Requests',
          [{ resource: 'nonprofitcheck', reason: 'Rate limit exceeded' }],
          checksUsedThisCycle,
        ),
        { 'retry-after': '1' },
      );
    }

    if (ein === CONTROL_EINS.transientFailure) {
      if (transientFailuresLeft > 0) {
        transientFailuresLeft -= 1;

        return send(
          res,
          503,
          errorEnvelope(
            503,
            'Service Unavailable',
            [{ resource: 'nonprofitcheck', reason: 'Upstream temporarily unavailable' }],
            checksUsedThisCycle,
          ),
        );
      }

      transientFailuresLeft = TRANSIENT_FAILURES;
      checksUsedThisCycle += 1;

      return send(
        res,
        200,
        envelope(fixtureOrganization(FIXTURE_EINS.publicCharity), null, checksUsedThisCycle),
      );
    }

    if (ein === CONTROL_EINS.slow) {
      const timer = setTimeout(() => {
        pendingTimers.delete(timer);
        checksUsedThisCycle += 1;
        send(
          res,
          200,
          envelope(fixtureOrganization(FIXTURE_EINS.publicCharity), null, checksUsedThisCycle),
        );
      }, SLOW_RESPONSE_MS);

      pendingTimers.add(timer);
      res.on('close', () => {
        clearTimeout(timer);
        pendingTimers.delete(timer);
      });

      return undefined;
    }

    if (!hasFixture(ein)) {
      return send(
        res,
        404,
        errorEnvelope(
          404,
          'Not Found',
          [
            {
              resource: 'nonprofitcheck',
              reason: 'A nonprofit with this EIN does not exist in our records',
            },
          ],
          checksUsedThisCycle,
        ),
      );
    }

    checksUsedThisCycle += 1;

    return send(res, 200, envelope(fixtureOrganization(ein), null, checksUsedThisCycle));
  }

  function handleBulk(res, eins) {
    if (!Array.isArray(eins)) {
      return send(
        res,
        400,
        errorEnvelope(
          400,
          'Bad Request',
          [
            {
              resource: 'nonprofitcheckbulk',
              reason:
                'The nonprofit check bulk API expects an array of EINs as part of the HTTP POST request body',
            },
          ],
          checksUsedThisCycle,
        ),
      );
    }

    if (eins.length > MAX_BULK_EINS) {
      return send(
        res,
        400,
        errorEnvelope(
          400,
          'Bad Request',
          [
            {
              resource: 'nonprofitcheckbulk',
              reason: `A maximum of ${MAX_BULK_EINS} EINs can be supplied to the nonprofit check bulk API`,
            },
          ],
          checksUsedThisCycle,
        ),
      );
    }

    // Every submitted EIN is counted, duplicates included.
    checksUsedThisCycle += eins.length;

    // The real service selects with `WHERE ein IN (...)`: duplicates collapse to
    // one row and the result order is the database's, not the request's. Sorting
    // here keeps that difference visible instead of accidentally matching.
    const matched = [...new Set(eins)].filter(hasFixture).sort();
    const notFound = eins.filter(ein => !hasFixture(ein));

    // Unmatched EINs are refunded, so the count reflects records actually served.
    checksUsedThisCycle -= notFound.length;

    if (matched.length === 0) {
      return send(
        res,
        404,
        errorEnvelope(
          404,
          'Not Found',
          [
            {
              resource: 'nonprofitcheckbulk',
              reason: 'There are no matching nonprofits in our records for this set of EINs',
            },
          ],
          checksUsedThisCycle,
        ),
      );
    }

    const errors =
      notFound.length === 0
        ? null
        : [
            {
              resource: 'nonprofitcheckbulk',
              reason: 'There are no matching nonprofits in our records for this set of EINs',
              code: 404,
              eins: notFound,
            },
          ];

    return send(res, 200, envelope(matched.map(fixtureOrganization), errors, checksUsedThisCycle));
  }

  const server = createServer(async (req, res) => {
    if (req.headers.authorization !== `Bearer ${validKey}`) {
      return send(res, 401, {
        code: 401,
        message: 'Unauthorized',
        errors: [{ resource: 'nonprofitcheck', reason: 'Invalid API Key' }],
        data: null,
      });
    }

    const url = new URL(req.url ?? '/', 'http://localhost');
    const single = url.pathname.match(SINGLE_PATH);

    if (req.method === 'GET' && single) {
      return handleSingle(res, single[1]);
    }

    if (req.method === 'POST' && url.pathname === BULK_PATH) {
      return handleBulk(res, await readJson(req));
    }

    return send(res, 404, { code: 404, message: 'Not Found', errors: null, data: null });
  });

  return new Promise(resolve => {
    server.listen(port, '127.0.0.1', () => {
      const address = server.address();

      resolve({
        server,
        url: `http://127.0.0.1:${address.port}`,
        /** Stops the server and clears any deferred response, leaving no open handles. */
        close() {
          for (const timer of pendingTimers) {
            clearTimeout(timer);
          }

          pendingTimers.clear();
          server.close();
        },
      });
    });
  });
}

// Allow running standalone: `node scripts/mock-server.mjs 4010`
if (import.meta.url === `file://${process.argv[1]}`) {
  const { url } = await startMockServer({ port: Number(process.argv[2] ?? 4010) });
  console.log(`Mock Pactman API listening on ${url}`);
}
