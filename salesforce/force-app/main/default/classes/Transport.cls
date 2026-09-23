/**
 * The HTTP layer: header assembly, response parsing, and the error taxonomy.
 *
 * **Retries work differently here than in the other SDKs, because Apex cannot
 * sleep.** There is no `Thread.sleep` equivalent, and a busy-wait loop burns
 * against the 10-second synchronous CPU limit and takes the whole transaction
 * down with it. So the exponential backoff the Node, Python and PHP clients use
 * is not implementable in a synchronous Apex transaction, and this SDK does not
 * pretend otherwise:
 *
 * - A callout that returns **no response at all** is retried once, immediately,
 *   for a single check and a bulk check alike — the other SDKs retry a transport
 *   failure on either endpoint, and one immediate attempt is as close as Apex
 *   can come without a sleep.
 * - A **timeout** is never retried. It has already consumed its share of the
 *   transaction's 120-second cumulative callout budget.
 * - An **HTTP error**, including 429 and 503, is never retried in-transaction.
 *   `Retry-After` is surfaced on the exception instead; hand it to
 *   {@link CheckQueueable} to retry asynchronously, which is the only place
 *   Apex offers real backoff.
 *
 * Package-internal.
 */
public class Transport {
    /** Attempts after the first, for a callout that produced no response. */
    private static final Integer MAX_IMMEDIATE_RETRIES = 1;

    private final Config config;

    public Transport(Config config) {
        this.config = config;
    }

    public TransportResponse send(String method, String path, Object body, RequestOptions options) {
        HttpRequest request = buildRequest(method, path, body, options);
        Integer timeoutMs = resolveTimeout(options);
        Integer attempts = 0;
        HttpResponse response;

        while (true) {
            guardCalloutLimit();
            attempts++;

            try {
                response = new Http().send(request);
                break;
            } catch (System.CalloutException e) {
                if (isTimeout(e)) {
                    throw Errors.timeout(
                        'The Pactman API did not respond within ' + timeoutMs + 'ms.',
                        timeoutMs,
                        attempts
                    );
                }

                if (attempts > MAX_IMMEDIATE_RETRIES) {
                    throw Errors.network(
                        'The callout to the Pactman API produced no response: ' + e.getMessage(),
                        attempts
                    );
                }
            }
        }

        TransportResponse parsed = parse(response);

        if (!parsed.isSuccess()) {
            throw errorFor(parsed, attempts);
        }

        return parsed;
    }

    /**
     * Normalizes the envelope's `errors` into a list.
     *
     * The API sends an array, a bare object, or a string depending on the
     * failure; all three become a list so callers never branch on shape.
     */
    public static List<ApiErrorDetail> normalizeApiErrors(Object errors) {
        List<ApiErrorDetail> result = new List<ApiErrorDetail>();

        if (errors == null) {
            return result;
        }

        if (errors instanceof List<Object>) {
            for (Object entry : (List<Object>) errors) {
                if (entry instanceof Map<String, Object>) {
                    result.add(new ApiErrorDetail((Map<String, Object>) entry));
                }
            }
        } else if (errors instanceof String) {
            String text = (String) errors;

            if (String.isNotBlank(text)) {
                result.add(new ApiErrorDetail(new Map<String, Object>{ 'reason' => text }));
            }
        } else if (errors instanceof Map<String, Object>) {
            result.add(new ApiErrorDetail((Map<String, Object>) errors));
        }

        return result;
    }

    private HttpRequest buildRequest(String method, String path, Object body, RequestOptions options) {
        HttpRequest request = new HttpRequest();
        request.setEndpoint(config.resolvedEndpoint() + path);
        request.setMethod(method);
        request.setTimeout(resolveTimeout(options));

        Map<String, String> callerHeaders = config.headers();

        if (options != null) {
            callerHeaders.putAll(options.headerMap());
        }

        // Set last, and a caller's spelling of the same name skipped, so neither
        // the client defaults nor a per-request header can misdeclare what this
        // SDK sends or accepts.
        for (String name : callerHeaders.keySet()) {
            String lower = name.toLowerCase();

            if (lower == 'accept' || lower == 'user-agent' || (body != null && lower == 'content-type')) {
                continue;
            }

            request.setHeader(name, callerHeaders.get(name));
        }

        request.setHeader('Accept', 'application/json');
        request.setHeader('User-Agent', SdkVersion.userAgent());

        if (body != null) {
            request.setHeader('Content-Type', 'application/json');
            request.setBody(JSON.serialize(body));
        }

        return request;
    }

    private Integer resolveTimeout(RequestOptions options) {
        if (options != null && options.timeoutMs != null) {
            return options.timeoutMs;
        }

        return config.timeoutMs;
    }

    /**
     * Refuses to send when the transaction has no callout budget left.
     *
     * Failing here with an SDK error names the real problem; letting the
     * platform throw surfaces a bare governor limit with no context.
     */
    private void guardCalloutLimit() {
        if (Limits.getCallouts() >= Limits.getLimitCallouts()) {
            throw Errors.configuration(
                'This transaction has already used all ' + Limits.getLimitCallouts() +
                    ' of its callouts. Move the remaining checks into a Queueable — see ' +
                    'CheckQueueable — or batch more EINs per request with checkBulk.'
            );
        }
    }

    private Boolean isTimeout(System.CalloutException e) {
        String message = e.getMessage();
        return message != null &&
            (message.containsIgnoreCase('timed out') || message.containsIgnoreCase('timeout'));
    }

    private TransportResponse parse(HttpResponse response) {
        TransportResponse parsed = new TransportResponse();
        parsed.status = response.getStatusCode();
        parsed.requestId = readRequestId(response);
        parsed.retryAfterSeconds = parseRetryAfter(headerIgnoringCase(response, 'Retry-After'));

        String text = response.getBody();

        if (String.isBlank(text)) {
            return parsed;
        }

        try {
            Object decoded = JSON.deserializeUntyped(text);
            parsed.raw = decoded;

            if (decoded instanceof Map<String, Object>) {
                parsed.envelope = (Map<String, Object>) decoded;
            }
        } catch (Exception e) {
            // A non-JSON body is evidence, not something to discard.
            parsed.raw = text;
        }

        return parsed;
    }

    private PactmanException errorFor(TransportResponse parsed, Integer attempts) {
        Map<String, Object> envelope = parsed.envelopeOrEmpty();

        ApiErrorInit details = new ApiErrorInit();
        details.status = parsed.status;
        details.apiErrors = normalizeApiErrors(envelope.get('errors'));
        details.apiMessage = apiMessageFor(envelope, details.apiErrors, parsed.raw);
        details.apiCode = DataObject.asInteger(envelope.get('code'));
        details.requestId = parsed.requestId;
        details.retryAfterSeconds = parsed.retryAfterSeconds;
        details.raw = parsed.raw;
        details.attempts = attempts;

        return Errors.fromStatus(details);
    }

    /**
     * The message an API error carries, chosen as every SDK chooses it: the
     * `reason` of each entry in `errors`, joined; else the envelope's `message`;
     * else the first 500 characters of a body that was not JSON. `null` sends
     * {@link Errors#fromStatus} to its default for the status.
     */
    @TestVisible
    private static String apiMessageFor(Map<String, Object> envelope, List<ApiErrorDetail> apiErrors, Object raw) {
        List<String> reasons = new List<String>();

        for (ApiErrorDetail detail : apiErrors) {
            if (String.isNotBlank(detail.reason)) {
                reasons.add(detail.reason);
            }
        }

        if (!reasons.isEmpty()) {
            return String.join(reasons, '; ');
        }

        if (envelope.get('message') instanceof String) {
            return (String) envelope.get('message');
        }

        if (raw instanceof String && String.isNotBlank((String) raw)) {
            return ((String) raw).trim().left(500);
        }

        return null;
    }

    private static final Map<String, Integer> MONTHS = new Map<String, Integer>{
        'Jan' => 1, 'Feb' => 2, 'Mar' => 3, 'Apr' => 4, 'May' => 5, 'Jun' => 6,
        'Jul' => 7, 'Aug' => 8, 'Sep' => 9, 'Oct' => 10, 'Nov' => 11, 'Dec' => 12
    };

    /**
     * Reads `Retry-After` as either a delay in seconds or an HTTP date.
     *
     * A date in the past yields `0` rather than a negative delay. An
     * unparseable value yields `null` — the SDK reports what the server sent or
     * nothing, it never guesses a delay.
     */
    private static Decimal parseRetryAfter(String value) {
        if (String.isBlank(value)) {
            return null;
        }

        String trimmed = value.trim();

        if (trimmed.isNumeric()) {
            return Decimal.valueOf(trimmed);
        }

        Datetime expiresAt = parseHttpDate(trimmed);

        if (expiresAt == null) {
            return null;
        }

        Decimal seconds = Decimal.valueOf(expiresAt.getTime() - Datetime.now().getTime()) / 1000;
        return seconds < 0 ? 0 : seconds;
    }

    /** Parses an RFC 1123 date such as `Wed, 21 Oct 2015 07:28:00 GMT`. */
    private static Datetime parseHttpDate(String value) {
        try {
            List<String> parts = value.replace(',', ' ').trim().split('\\s+');

            if (parts.size() < 5) {
                return null;
            }

            Integer month = MONTHS.get(parts[2].capitalize());
            List<String> clockParts = parts[4].split(':');

            if (month == null || clockParts.size() < 3) {
                return null;
            }

            return Datetime.newInstanceGmt(
                Integer.valueOf(parts[3]),
                month,
                Integer.valueOf(parts[1]),
                Integer.valueOf(clockParts[0]),
                Integer.valueOf(clockParts[1]),
                Integer.valueOf(clockParts[2])
            );
        } catch (Exception e) {
            return null;
        }
    }

    /** Matches the header precedence the other SDKs use. */
    private String readRequestId(HttpResponse response) {
        for (String candidate : new List<String>{ 'x-request-id', 'x-correlation-id', 'request-id' }) {
            String value = headerIgnoringCase(response, candidate);

            if (String.isNotBlank(value)) {
                return value;
            }
        }

        return null;
    }

    private String headerIgnoringCase(HttpResponse response, String name) {
        for (String key : response.getHeaderKeys()) {
            if (key != null && key.equalsIgnoreCase(name)) {
                return response.getHeader(key);
            }
        }

        return null;
    }
}
