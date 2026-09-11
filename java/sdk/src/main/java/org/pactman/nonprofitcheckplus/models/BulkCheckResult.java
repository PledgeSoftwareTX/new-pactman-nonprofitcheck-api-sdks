package org.pactman.nonprofitcheckplus.models;

import java.util.Collections;
import java.util.List;

/**
 * The result of
 * {@link org.pactman.nonprofitcheckplus.NonprofitsResource#checkBulk(java.util.List)}.
 */
public final class BulkCheckResult extends PactmanResult {

    private final List<Nonprofit> organizations;
    private final List<String> notFoundEins;

    /**
     * Initializes the result.
     *
     * @param organizations the organizations the API matched.
     * @param notFoundEins  EINs the API reported no record for.
     * @param checkCount    checks consumed in the current billing cycle, or {@code null}.
     * @param timeTakenMs   server-side processing time, or {@code null}.
     * @param errors        item-level failures the API reported alongside the response.
     * @param requestId     correlation identifier from the response headers, or {@code null}.
     * @param status        the HTTP status of the response.
     * @param raw           the unmodified parsed response body.
     */
    public BulkCheckResult(
            List<Nonprofit> organizations,
            List<String> notFoundEins,
            Integer checkCount,
            Double timeTakenMs,
            List<ApiErrorDetail> errors,
            String requestId,
            int status,
            ResponseBody raw) {
        super(checkCount, timeTakenMs, errors, requestId, status, raw);
        this.organizations = organizations == null
                ? Collections.<Nonprofit>emptyList()
                : Collections.unmodifiableList(organizations);
        this.notFoundEins = notFoundEins == null
                ? Collections.<String>emptyList()
                : Collections.unmodifiableList(notFoundEins);
    }

    /**
     * Organizations the API matched, in the order it returned them — which is
     * not guaranteed to follow the order you supplied.
     *
     * <p>Index by {@link Nonprofit#getEin()} rather than pairing positionally
     * with your input.
     *
     * @return the organizations.
     */
    public List<Nonprofit> getOrganizations() {
        return organizations;
    }

    /**
     * EINs the API reported no record for, collected from {@link #getErrors()}.
     *
     * <p>A bulk request where some EINs miss is a successful HTTP 200, not an
     * error.
     *
     * @return the EINs with no record.
     */
    public List<String> getNotFoundEins() {
        return notFoundEins;
    }
}
