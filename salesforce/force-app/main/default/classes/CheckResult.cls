/**
 * Fields shared by every result this SDK returns.
 *
 * Results are shapes this SDK defines, so they carry real typed members —
 * unlike {@link Nonprofit}, whose shape the wire dictates.
 *
 * The constructor is `public`, not `global`: the SDK builds these, subscribers
 * only read them.
 */
global abstract class CheckResult {
    /**
     * `nonprofit_check_count` from the envelope: checks consumed so far in the
     * current billing cycle, including this request, resetting each cycle.
     *
     * Not the size of this request. Take the delta between two responses if you
     * need that, and read this one as a usage gauge.
     */
    global Integer checkCount { get; private set; }

    /** Server-side processing time in milliseconds, when reported. */
    global Decimal timeTakenMs { get; private set; }

    /**
     * Item-level failures reported alongside a successful response. Empty when
     * the API reported none.
     */
    global List<ApiErrorDetail> errors { get; private set; }

    /** Correlation identifier from the response headers, when the server sent one. */
    global String requestId { get; private set; }

    /** HTTP status of the response. */
    global Integer status { get; private set; }

    /**
     * The unmodified parsed response body, including any field not typed above.
     *
     * Normally the parsed envelope as a `Map<String, Object>`; a server that
     * answers 200 with a non-JSON body leaves the raw text here rather than
     * discarding the evidence.
     */
    global Object raw { get; private set; }

    public CheckResult(
        Integer checkCount,
        Decimal timeTakenMs,
        List<ApiErrorDetail> errors,
        String requestId,
        Integer status,
        Object raw
    ) {
        this.checkCount = checkCount;
        this.timeTakenMs = timeTakenMs;
        this.errors = errors == null ? new List<ApiErrorDetail>() : errors;
        this.requestId = requestId;
        this.status = status;
        this.raw = raw;
    }
}
