/**
 * A stand-in for the Nonprofit Check Plus API, so that the examples run in a
 * scratch org with no key and no network.
 *
 * The package ships {@link FixtureMock} for subscribers to test their own code
 * with, and it is the right tool for that job: a couple of lines, one seeded
 * EIN, done. The examples need more than it offers — a cumulative check count
 * that actually moves, bulk set-membership semantics, and control EINs that
 * produce a rate limit, a lost response or a timeout — so they use this,
 * which serves the same records as the Node, Python, Go, Java and .NET mock
 * servers.
 *
 * This is a port of the Node SDK's `scripts/mock-server.mjs`.
 */
@IsTest
public class ExampleApiMock implements HttpCalloutMock {
    /** How many times CONTROL_TRANSIENT_FAILURE fails before succeeding. */
    private static final Integer TRANSIENT_FAILURES = 2;

    private static final String BULK_MARKER = 'nonprofitcheckbulk';

    private final Map<String, Map<String, Object>> organizations;

    /**
     * A running total for the billing cycle, as the real service reports it —
     * not the size of the current request.
     */
    private Integer checksUsed = 0;

    private Integer transientLeft = TRANSIENT_FAILURES;

    /** How many requests this mock has answered, for the examples that count. */
    public Integer requests { get; private set; }

    public ExampleApiMock() {
        this.organizations = ExampleFixtures.organizations();
        this.requests = 0;
    }

    /** A client pointed at this mock. The endpoint is never actually reached. */
    public static Client client() {
        return new Client(config());
    }

    /** The configuration the examples use. Carries no credential — none exists. */
    public static Config config() {
        return new Config().withEndpoint('https://pactman.example');
    }

    /** True when the mock holds a record for the EIN. */
    public Boolean hasRecord(String ein) {
        return organizations.containsKey(ein);
    }

    /** The record for an EIN, so an example can compare against what was served. */
    public Map<String, Object> record(String ein) {
        return organizations.get(ein);
    }

    public HttpResponse respond(HttpRequest request) {
        requests++;

        if (request.getEndpoint().contains(BULK_MARKER)) {
            return bulk(request);
        }

        return single(request.getEndpoint().substringAfterLast('/'));
    }

    private HttpResponse single(String ein) {
        if (ein == ExampleFixtures.CONTROL_RATE_LIMITED) {
            HttpResponse response = failure(429, 'Too Many Requests', 'Rate limit exceeded');
            response.setHeader('Retry-After', '1');

            return response;
        }

        if (ein == ExampleFixtures.CONTROL_SLOW) {
            // Apex surfaces a timeout as a CalloutException whose message says
            // so; the SDK turns that into a TimeoutException.
            throw new CalloutException('Read timed out');
        }

        if (ein == ExampleFixtures.CONTROL_TRANSIENT_FAILURE) {
            if (transientLeft > 0) {
                transientLeft--;

                throw new CalloutException('Unable to tunnel through proxy');
            }

            transientLeft = TRANSIENT_FAILURES;

            return served(ExampleFixtures.PUBLIC_CHARITY);
        }

        if (!hasRecord(ein)) {
            return failure(
                404,
                'Not Found',
                'A nonprofit with this EIN does not exist in our records'
            );
        }

        return served(ein);
    }

    private HttpResponse served(String ein) {
        checksUsed++;

        return json(
            200,
            new Map<String, Object>{
                'code' => 200,
                'message' => 'OK',
                'errors' => new List<Object>(),
                'data' => organizations.get(ein),
                'timeTaken' => 12,
                'nonprofit_check_count' => checksUsed
            }
        );
    }

    private HttpResponse bulk(HttpRequest request) {
        List<Object> requested;

        try {
            requested = (List<Object>) JSON.deserializeUntyped(request.getBody());
        } catch (Exception malformed) {
            return failure(
                400,
                'Bad Request',
                'The nonprofit check bulk API expects an array of EINs as part of the ' +
                    'HTTP POST request body'
            );
        }

        if (requested.size() > Constants.MAX_BULK_EINS) {
            return failure(
                400,
                'Bad Request',
                'A maximum of ' + Constants.MAX_BULK_EINS +
                    ' EINs can be supplied to the nonprofit check bulk API'
            );
        }

        // The real service selects with WHERE ein IN (...): duplicates collapse
        // to one row and the order is the database's, not the request's.
        // Sorting keeps that difference visible instead of accidentally
        // matching.
        Set<String> seen = new Set<String>();
        List<String> matched = new List<String>();
        List<Object> missing = new List<Object>();

        for (Object entry : requested) {
            String ein = String.valueOf(entry);

            if (!hasRecord(ein)) {
                missing.add(ein);
            } else if (seen.add(ein)) {
                matched.add(ein);
            }
        }

        matched.sort();

        // Every submitted EIN is counted, duplicates included; unmatched ones
        // are refunded, so the count reflects records actually served.
        checksUsed += requested.size() - missing.size();

        final String noMatches =
            'There are no matching nonprofits in our records for this set of EINs';

        if (matched.isEmpty()) {
            return json(
                404,
                new Map<String, Object>{
                    'code' => 404,
                    'message' => 'Not Found',
                    'errors' => new List<Object>{
                        detail('nonprofitcheckbulk', noMatches, 404, missing)
                    },
                    'nonprofit_check_count' => checksUsed
                }
            );
        }

        List<Object> data = new List<Object>();

        for (String ein : matched) {
            data.add(organizations.get(ein));
        }

        List<Object> errors = new List<Object>();

        if (!missing.isEmpty()) {
            errors.add(detail('nonprofitcheckbulk', noMatches, 404, missing));
        }

        return json(
            200,
            new Map<String, Object>{
                'code' => 200,
                'message' => 'OK',
                'errors' => errors,
                'data' => data,
                'timeTaken' => 31,
                'nonprofit_check_count' => checksUsed
            }
        );
    }

    private HttpResponse failure(Integer status, String message, String reason) {
        return json(
            status,
            new Map<String, Object>{
                'code' => status,
                'message' => message,
                'errors' => new List<Object>{
                    detail(status == 400 ? 'nonprofitcheckbulk' : 'nonprofitcheck', reason, null, null)
                },
                'nonprofit_check_count' => checksUsed
            }
        );
    }

    private Map<String, Object> detail(
        String resource,
        String reason,
        Integer code,
        List<Object> eins
    ) {
        Map<String, Object> entry = new Map<String, Object>{
            'resource' => resource,
            'reason' => reason
        };

        if (code != null) {
            entry.put('code', code);
        }

        if (eins != null && !eins.isEmpty()) {
            entry.put('eins', eins);
        }

        return entry;
    }

    private HttpResponse json(Integer status, Map<String, Object> body) {
        HttpResponse response = new HttpResponse();
        response.setStatusCode(status);
        response.setHeader('Content-Type', 'application/json');
        response.setHeader('x-request-id', 'example-' + String.valueOf(requests));
        response.setBody(JSON.serialize(body));

        return response;
    }
}
