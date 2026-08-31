/**
 * Builds the SDK's exceptions and renders them for logging.
 *
 * The factory methods are package-internal — subscribers catch these
 * exceptions, they never construct them. {@link wireValue} and {@link toMap}
 * are `global` because structured logging needs them.
 */
global class Errors {
    /**
     * The stable wire string for a category — `bad_request`, `not_found`, and
     * so on.
     *
     * Derived from the constant name rather than a parallel lookup table, so
     * the two cannot drift. `ErrorsTest` pins every value explicitly, which is
     * what makes renaming a constant a deliberate, failing change.
     */
    global static String wireValue(ErrorCategory category) {
        return category == null ? null : category.name().toLowerCase();
    }

    /** The stable wire string for an origin — `local` or `api`. */
    global static String wireValue(ErrorOrigin origin) {
        return origin == null ? null : origin.name().toLowerCase();
    }

    /**
     * A serializable view of an exception, for logs. Never contains the API key
     * — the key is not reachable from Apex at all.
     */
    global static Map<String, Object> toMap(PactmanException e) {
        if (e == null) {
            return null;
        }

        Map<String, Object> result = new Map<String, Object>{
            'name' => e.getTypeName(),
            'message' => e.getMessage(),
            'category' => wireValue(e.category),
            'origin' => wireValue(e.origin)
        };

        if (e instanceof ValidationException) {
            List<Map<String, Object>> issues = new List<Map<String, Object>>();

            for (ValidationIssue issue : ((ValidationException) e).issues) {
                issues.add(issue.toMap());
            }

            result.put('issues', issues);
        } else if (e instanceof ApiException) {
            ApiException api = (ApiException) e;
            result.put('status', api.status);
            result.put('apiMessage', api.apiMessage);
            result.put('apiCode', api.apiCode);
            result.put('requestId', api.requestId);
            result.put('retryAfterSeconds', api.retryAfterSeconds);
            result.put('attempts', api.attempts);
        } else if (e instanceof TimeoutException) {
            TimeoutException t = (TimeoutException) e;
            result.put('timeoutMs', t.timeoutMs);
            result.put('attempts', t.attempts);
        } else if (e instanceof NetworkException) {
            result.put('attempts', ((NetworkException) e).attempts);
        }

        return result;
    }

    /** Package-internal. */
    public static ConfigurationException configuration(String message) {
        ConfigurationException e = new ConfigurationException(message);
        e.init(ErrorCategory.CONFIGURATION, ErrorOrigin.LOCAL);
        return e;
    }

    /** Package-internal. */
    public static ValidationException validation(String message, List<ValidationIssue> issues) {
        ValidationException e = new ValidationException(message);
        e.init(ErrorCategory.VALIDATION, ErrorOrigin.LOCAL);
        e.initIssues(issues);
        return e;
    }

    /** Package-internal. */
    public static TimeoutException timeout(String message, Integer timeoutMs, Integer attempts) {
        TimeoutException e = new TimeoutException(message);
        e.init(ErrorCategory.TIMEOUT, ErrorOrigin.LOCAL);
        e.initTimeout(timeoutMs, attempts);
        return e;
    }

    /** Package-internal. */
    public static NetworkException network(String message, Integer attempts) {
        NetworkException e = new NetworkException(message);
        e.init(ErrorCategory.NETWORK, ErrorOrigin.LOCAL);
        e.initNetwork(attempts);
        return e;
    }

    /**
     * Builds the exception subclass that matches an HTTP status code.
     *
     * Package-internal.
     */
    public static ApiException fromStatus(ApiErrorInit details) {
        String message = String.isNotBlank(details.apiMessage)
            ? details.apiMessage.trim()
            : defaultMessageForStatus(details.status);

        ApiException e;
        ErrorCategory category;

        if (details.status == 400) {
            e = new BadRequestException(message);
            category = ErrorCategory.BAD_REQUEST;
        } else if (details.status == 401) {
            e = new AuthenticationException(message);
            category = ErrorCategory.AUTHENTICATION;
        } else if (details.status == 403) {
            e = new AuthorizationException(message);
            category = ErrorCategory.AUTHORIZATION;
        } else if (details.status == 404) {
            e = new NotFoundException(message);
            category = ErrorCategory.NOT_FOUND;
        } else if (details.status == 429) {
            e = new RateLimitException(message);
            category = ErrorCategory.RATE_LIMIT;
        } else if (details.status >= 500) {
            e = new ServerException(message);
            category = ErrorCategory.SERVER;
        } else {
            e = new ApiException(message);
            category = ErrorCategory.API;
        }

        e.init(category, ErrorOrigin.API);
        e.initApi(details);
        return e;
    }

    private static String defaultMessageForStatus(Integer status) {
        if (status == 400) {
            return 'The Pactman API rejected the request.';
        }
        if (status == 401) {
            return 'The Pactman API key was rejected.';
        }
        if (status == 403) {
            return 'This Pactman API key is not permitted to access that resource.';
        }
        if (status == 404) {
            return 'No matching record was found.';
        }
        if (status == 429) {
            return 'The Pactman API rate limit was exceeded.';
        }
        if (status >= 500) {
            return 'The Pactman API returned a server error (HTTP ' + status + ').';
        }
        return 'The Pactman API returned an unexpected response (HTTP ' + status + ').';
    }
}
