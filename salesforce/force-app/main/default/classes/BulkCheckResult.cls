/** The result of {@link Nonprofits.checkBulk}. */
global class BulkCheckResult extends CheckResult {
    /**
     * Organizations the API matched, in the order it returned them — which is
     * not guaranteed to follow the order you supplied. Index by EIN with
     * {@link byEin} rather than pairing positionally.
     */
    global List<Nonprofit> organizations { get; private set; }

    /**
     * EINs the API reported no record for, collected from `errors`.
     *
     * A bulk request where some EINs miss is a successful HTTP 200, not an
     * error.
     */
    global List<String> notFoundEins { get; private set; }

    public BulkCheckResult(
        Integer checkCount,
        Decimal timeTakenMs,
        List<ApiErrorDetail> errors,
        String requestId,
        Integer status,
        Object raw,
        List<Nonprofit> organizations,
        List<String> notFoundEins
    ) {
        super(checkCount, timeTakenMs, errors, requestId, status, raw);
        this.organizations = organizations == null ? new List<Nonprofit>() : organizations;
        this.notFoundEins = notFoundEins == null ? new List<String>() : notFoundEins;
    }

    /**
     * The matched organizations keyed by their normalized EIN.
     *
     * The API matches by set membership, so a repeated EIN comes back once and
     * the response order does not follow the request order. This is the safe
     * way to pair results back to your input. An organization the API returned
     * without an `ein` field is skipped.
     */
    global Map<String, Nonprofit> byEin() {
        Map<String, Nonprofit> result = new Map<String, Nonprofit>();

        for (Nonprofit organization : organizations) {
            String ein = organization.ein;

            if (String.isNotBlank(ein)) {
                result.put(ein, organization);
            }
        }

        return result;
    }
}
