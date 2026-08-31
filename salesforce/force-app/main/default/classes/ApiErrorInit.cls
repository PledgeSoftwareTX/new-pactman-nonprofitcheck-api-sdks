/**
 * Fields shared by every exception derived from an HTTP response.
 *
 * Package-internal carrier, mirroring `PactmanApiErrorInit` in the Node SDK.
 * Deliberately not `global`: subscribers read these off the exception, they
 * never build one.
 */
public class ApiErrorInit {
    public Integer status;
    public String apiMessage;
    public Integer apiCode;
    public List<ApiErrorDetail> apiErrors;
    public String requestId;
    public Decimal retryAfterSeconds;
    public Object raw;
    public Integer attempts = 1;
}
