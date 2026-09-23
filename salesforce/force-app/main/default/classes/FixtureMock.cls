/**
 * An `HttpCalloutMock` that serves plausible Pactman responses.
 *
 * **This ships with the package on purpose.** Subscriber orgs cannot make
 * callouts in tests either, and they cannot mock this SDK's internal HTTP layer
 * across a namespace boundary — so without a supplied mock, every customer test
 * that touches the SDK fails. None of the other Pactman SDKs need an equivalent.
 *
 * ```
 * Test.setMock(HttpCalloutMock.class, new pactman.FixtureMock().withOrganization('41-1787097'));
 * Test.startTest();
 * pactman.SingleCheckResult result = new pactman.Client().nonprofits.check('41-1787097');
 * Test.stopTest();
 * ```
 *
 * Seed the EINs your test expects to resolve. An unseeded EIN comes back as a
 * 404 for a single check, and in `notFoundEins` for a bulk check — the same way
 * the live API reports it.
 */
@IsTest
global class FixtureMock implements HttpCalloutMock {
    private final Map<String, Map<String, Object>> organizations = new Map<String, Map<String, Object>>();
    private final Map<String, String> headers = new Map<String, String>{ 'x-request-id' => 'fixture-request-id' };
    private Integer status = 200;
    private String forcedBody;
    private String forcedMessage;
    private Integer checkCount = 1;

    /** Seeds an EIN with a realistic record. */
    global FixtureMock withOrganization(String einValue) {
        return withOrganization(einValue, sampleOrganization(einValue));
    }

    /** Seeds an EIN with fields of your choosing. */
    global FixtureMock withOrganization(String einValue, Map<String, Object> fields) {
        organizations.put(Ein.normalize(einValue), fields);
        return this;
    }

    /**
     * Forces every response to this HTTP status.
     *
     * Use it to exercise your error handling — `withStatus(429)` plus
     * `withHeader('Retry-After', '30')` reproduces a rate limit.
     */
    global FixtureMock withStatus(Integer status) {
        this.status = status;
        return this;
    }

    /** Sets the `message` returned in the error envelope. */
    global FixtureMock withMessage(String message) {
        this.forcedMessage = message;
        return this;
    }

    /** Returns this exact body, whatever was requested. For malformed-response tests. */
    global FixtureMock withBody(String body) {
        this.forcedBody = body;
        return this;
    }

    /** Sets a response header. */
    global FixtureMock withHeader(String name, String value) {
        headers.put(name, value);
        return this;
    }

    /** Sets the `nonprofit_check_count` reported in the envelope. */
    global FixtureMock withCheckCount(Integer count) {
        this.checkCount = count;
        return this;
    }

    /** A realistic record for `ein`, for tests that do not care about specific values. */
    global static Map<String, Object> sampleOrganization(String einValue) {
        String normalized = Ein.normalize(einValue);

        return new Map<String, Object>{
            'ein' => normalized,
            'organization_name' => 'Fixture Charitable Trust',
            'city' => 'Austin',
            'state' => 'TX',
            'zip' => '78701',
            'pub78_verified' => true,
            'pub78_ein' => normalized,
            'pub78_indicator' => 'PC',
            'bmf_status' => true,
            'bmf_ein' => normalized,
            'bmf_subsection' => '03',
            'subsection_description' => 'Charitable Organization',
            'ofac_status' => 'No OFAC SDN match was found for this organization.',
            'irs_bmf_pub78_conflict' => false,
            'organization_types' => new List<Object>{
                new Map<String, Object>{
                    'organization_type' => 'PC',
                    'deductibility_limitation' => '50% (60% for cash contributions)',
                    'deductibility_status_description' => 'Contributions are deductible'
                }
            }
        };
    }

    global HttpResponse respond(HttpRequest request) {
        HttpResponse response = new HttpResponse();
        response.setStatusCode(status);

        for (String name : headers.keySet()) {
            response.setHeader(name, headers.get(name));
        }

        if (forcedBody != null) {
            response.setBody(forcedBody);
            return response;
        }

        response.setHeader('Content-Type', 'application/json');

        if (status >= 400) {
            response.setBody(JSON.serialize(new Map<String, Object>{
                'code' => status,
                'message' => forcedMessage == null ? 'Fixture error.' : forcedMessage,
                'errors' => new List<Object>()
            }));
            return response;
        }

        Boolean isBulk = request.getEndpoint().contains('nonprofitcheckbulk');
        response.setBody(isBulk ? bulkBody(request) : singleBody(request, response));
        return response;
    }

    private String singleBody(HttpRequest request, HttpResponse response) {
        String endpoint = request.getEndpoint();
        String ein = endpoint.substringAfterLast('/');
        Map<String, Object> record = organizations.get(ein);

        if (record == null) {
            response.setStatusCode(404);
            return JSON.serialize(new Map<String, Object>{
                'code' => 404,
                'message' => 'No matching record was found.',
                'errors' => new List<Object>{
                    new Map<String, Object>{
                        'resource' => 'nonprofitcheck',
                        'reason' => 'EIN not found.',
                        'code' => 404,
                        'eins' => new List<Object>{ ein }
                    }
                },
                'nonprofit_check_count' => checkCount
            });
        }

        return JSON.serialize(new Map<String, Object>{
            'code' => 200,
            'message' => 'Success',
            'errors' => new List<Object>(),
            'data' => record,
            'timeTaken' => 42,
            'nonprofit_check_count' => checkCount
        });
    }

    private String bulkBody(HttpRequest request) {
        List<Object> requested = (List<Object>) JSON.deserializeUntyped(request.getBody());
        List<Object> found = new List<Object>();
        List<Object> missing = new List<Object>();

        for (Object entry : requested) {
            String ein = String.valueOf(entry);

            if (organizations.containsKey(ein)) {
                found.add(organizations.get(ein));
            } else {
                missing.add(ein);
            }
        }

        List<Object> errors = new List<Object>();

        if (!missing.isEmpty()) {
            errors.add(new Map<String, Object>{
                'resource' => 'nonprofitcheckbulk',
                'reason' => 'No record was found for these EINs.',
                'code' => 404,
                'eins' => missing
            });
        }

        return JSON.serialize(new Map<String, Object>{
            'code' => 200,
            'message' => 'Success',
            'errors' => errors,
            'data' => found,
            'timeTaken' => 87,
            'nonprofit_check_count' => checkCount
        });
    }
}
