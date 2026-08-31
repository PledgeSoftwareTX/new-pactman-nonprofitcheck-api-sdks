/** One HTTP response, parsed. Package-internal. */
public class TransportResponse {
    public Integer status;

    /** The parsed envelope, or `null` when the body was not a JSON object. */
    public Map<String, Object> envelope;

    /** The parsed body, or the raw text when it was not JSON. */
    public Object raw;

    /** Correlation identifier from the response headers, when the server sent one. */
    public String requestId;

    /** `Retry-After` in seconds, when the server sent a value this SDK could read. */
    public Decimal retryAfterSeconds;

    public Boolean isSuccess() {
        return status >= 200 && status < 300;
    }

    /** The envelope, or an empty map when the body was not a JSON object. */
    public Map<String, Object> envelopeOrEmpty() {
        return envelope == null ? new Map<String, Object>() : envelope;
    }
}
