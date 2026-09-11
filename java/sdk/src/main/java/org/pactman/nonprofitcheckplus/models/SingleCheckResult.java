package org.pactman.nonprofitcheckplus.models;

import java.util.List;

/**
 * The result of
 * {@link org.pactman.nonprofitcheckplus.NonprofitsResource#check(String)}.
 */
public final class SingleCheckResult extends PactmanResult {

    private final Nonprofit nonprofit;

    /**
     * Initializes the result.
     *
     * @param nonprofit   the organization, or {@code null} when the API returned no record.
     * @param checkCount  checks consumed in the current billing cycle, or {@code null}.
     * @param timeTakenMs server-side processing time, or {@code null}.
     * @param errors      item-level failures the API reported alongside the response.
     * @param requestId   correlation identifier from the response headers, or {@code null}.
     * @param status      the HTTP status of the response.
     * @param raw         the unmodified parsed response body.
     */
    public SingleCheckResult(
            Nonprofit nonprofit,
            Integer checkCount,
            Double timeTakenMs,
            List<ApiErrorDetail> errors,
            String requestId,
            int status,
            ResponseBody raw) {
        super(checkCount, timeTakenMs, errors, requestId, status, raw);
        this.nonprofit = nonprofit;
    }

    /**
     * The organization the API matched.
     *
     * @return the organization, or {@code null} when the API returned no record.
     */
    public Nonprofit getNonprofit() {
        return nonprofit;
    }
}
