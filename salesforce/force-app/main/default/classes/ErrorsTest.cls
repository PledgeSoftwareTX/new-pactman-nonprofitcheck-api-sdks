/**
 * Pins the error taxonomy.
 *
 * The wire strings are derived from the enum constant names, so this test is
 * what makes renaming a constant a deliberate, failing change rather than a
 * silent break of parity with the Node, Python and PHP SDKs.
 */
@IsTest
private class ErrorsTest {
    @IsTest
    static void categoryWireValuesMatchTheOtherSdks() {
        Assert.areEqual('configuration', Errors.wireValue(ErrorCategory.CONFIGURATION));
        Assert.areEqual('validation', Errors.wireValue(ErrorCategory.VALIDATION));
        Assert.areEqual('authentication', Errors.wireValue(ErrorCategory.AUTHENTICATION));
        Assert.areEqual('authorization', Errors.wireValue(ErrorCategory.AUTHORIZATION));
        Assert.areEqual('bad_request', Errors.wireValue(ErrorCategory.BAD_REQUEST));
        Assert.areEqual('not_found', Errors.wireValue(ErrorCategory.NOT_FOUND));
        Assert.areEqual('rate_limit', Errors.wireValue(ErrorCategory.RATE_LIMIT));
        Assert.areEqual('server', Errors.wireValue(ErrorCategory.SERVER));
        Assert.areEqual('timeout', Errors.wireValue(ErrorCategory.TIMEOUT));
        Assert.areEqual('network', Errors.wireValue(ErrorCategory.NETWORK));
        Assert.areEqual('api', Errors.wireValue(ErrorCategory.API));
        Assert.areEqual(11, ErrorCategory.values().size(), 'A category was added or removed.');
    }

    @IsTest
    static void originWireValuesMatchTheOtherSdks() {
        Assert.areEqual('local', Errors.wireValue(ErrorOrigin.LOCAL));
        Assert.areEqual('api', Errors.wireValue(ErrorOrigin.API));
        Assert.areEqual(2, ErrorOrigin.values().size());
    }

    @IsTest
    static void statusMapsToTheMatchingSubclass() {
        Assert.isInstanceOfType(build(400), BadRequestException.class);
        Assert.isInstanceOfType(build(401), AuthenticationException.class);
        Assert.isInstanceOfType(build(403), AuthorizationException.class);
        Assert.isInstanceOfType(build(404), NotFoundException.class);
        Assert.isInstanceOfType(build(429), RateLimitException.class);
        Assert.isInstanceOfType(build(500), ServerException.class);
        Assert.isInstanceOfType(build(503), ServerException.class);
        Assert.isInstanceOfType(build(418), ApiException.class);
    }

    @IsTest
    static void categoriesFollowTheStatus() {
        Assert.areEqual(ErrorCategory.BAD_REQUEST, build(400).category);
        Assert.areEqual(ErrorCategory.RATE_LIMIT, build(429).category);
        Assert.areEqual(ErrorCategory.SERVER, build(500).category);
        Assert.areEqual(ErrorCategory.API, build(418).category);
        Assert.areEqual(ErrorOrigin.API, build(400).origin);
    }

    @IsTest
    static void fallsBackToADefaultMessagePerStatus() {
        Assert.areEqual('The Pactman API key was rejected.', build(401).getMessage());
        Assert.areEqual('No matching record was found.', build(404).getMessage());
        Assert.areEqual('The Pactman API rate limit was exceeded.', build(429).getMessage());
        Assert.areEqual(
            'The Pactman API returned a server error (HTTP 502).',
            build(502).getMessage()
        );
    }

    @IsTest
    static void prefersTheApiMessageWhenThereIsOne() {
        ApiErrorInit details = new ApiErrorInit();
        details.status = 400;
        details.apiMessage = '  EIN 12 is malformed.  ';

        Assert.areEqual('EIN 12 is malformed.', Errors.fromStatus(details).getMessage());
    }

    @IsTest
    static void toMapCarriesTheCategoryAndSubclassDetail() {
        ApiErrorInit details = new ApiErrorInit();
        details.status = 429;
        details.requestId = 'req-1';
        details.retryAfterSeconds = 30;
        details.attempts = 2;

        Map<String, Object> logged = Errors.toMap(Errors.fromStatus(details));

        Assert.areEqual('rate_limit', logged.get('category'));
        Assert.areEqual('api', logged.get('origin'));
        Assert.areEqual(429, logged.get('status'));
        Assert.areEqual('req-1', logged.get('requestId'));
        Assert.areEqual(30, ((Decimal) logged.get('retryAfterSeconds')).intValue());
        Assert.areEqual(2, logged.get('attempts'));
    }

    @IsTest
    static void toMapCarriesValidationIssues() {
        ValidationException e = Errors.validation(
            'bad',
            new List<ValidationIssue>{ new ValidationIssue('EIN at index 0 is empty.', 0, '') }
        );

        Map<String, Object> logged = Errors.toMap(e);

        Assert.areEqual('validation', logged.get('category'));
        Assert.areEqual('local', logged.get('origin'));
        Assert.areEqual(1, ((List<Map<String, Object>>) logged.get('issues')).size());
    }

    @IsTest
    static void toMapNeverMentionsACredential() {
        String logged = JSON.serialize(Errors.toMap(build(401)));

        Assert.isFalse(logged.containsIgnoreCase('authorization'), logged);
        Assert.isFalse(logged.containsIgnoreCase('bearer'), logged);
        Assert.isFalse(logged.containsIgnoreCase('apikey'), logged);
    }

    private static ApiException build(Integer status) {
        ApiErrorInit details = new ApiErrorInit();
        details.status = status;
        return Errors.fromStatus(details);
    }
}
