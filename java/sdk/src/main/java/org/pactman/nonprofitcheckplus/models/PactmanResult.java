package org.pactman.nonprofitcheckplus.models;

import java.util.Collections;
import java.util.List;

/** Fields shared by every result this SDK returns. */
public abstract class PactmanResult {

    private final Integer checkCount;
    private final Double timeTakenMs;
    private final List<ApiErrorDetail> errors;
    private final String requestId;
    private final int status;
    private final ResponseBody raw;

    /**
     * Initializes the shared fields.
     *
     * @param checkCount  checks consumed in the current billing cycle, or {@code null}.
     * @param timeTakenMs server-side processing time, or {@code null}.
     * @param errors      item-level failures the API reported alongside the response.
     * @param requestId   correlation identifier from the response headers, or {@code null}.
     * @param status      the HTTP status of the response.
     * @param raw         the unmodified parsed response body.
     */
    protected PactmanResult(
            Integer checkCount,
            Double timeTakenMs,
            List<ApiErrorDetail> errors,
            String requestId,
            int status,
            ResponseBody raw) {
        this.checkCount = checkCount;
        this.timeTakenMs = timeTakenMs;
        this.errors = errors == null
                ? Collections.<ApiErrorDetail>emptyList()
                : Collections.unmodifiableList(errors);
        this.requestId = requestId;
        this.status = status;
        this.raw = raw;
    }

    /**
     * {@code nonprofit_check_count} from the envelope: checks consumed so far in
     * the current billing cycle, including this request, resetting each cycle.
     *
     * <p>Not the size of this request. Take the delta between two responses if
     * you need that, and read this one as a usage gauge.
     *
     * @return the running total, or {@code null} when the API returned none.
     */
    public Integer getCheckCount() {
        return checkCount;
    }

    /**
     * Server-side processing time in milliseconds, when reported.
     *
     * @return the duration, or {@code null}.
     */
    public Double getTimeTakenMs() {
        return timeTakenMs;
    }

    /**
     * Item-level failures reported alongside a successful response.
     *
     * @return the details. Empty when the API reported none.
     */
    public List<ApiErrorDetail> getErrors() {
        return errors;
    }

    /**
     * Correlation identifier from the response headers, when the server sent one.
     *
     * @return the request id, or {@code null}.
     */
    public String getRequestId() {
        return requestId;
    }

    /**
     * The HTTP status of the response.
     *
     * @return the status code.
     */
    public int getStatus() {
        return status;
    }

    /**
     * The unmodified parsed response body, including any fields not typed above.
     *
     * @return the envelope.
     */
    public ResponseBody getRaw() {
        return raw;
    }
}
