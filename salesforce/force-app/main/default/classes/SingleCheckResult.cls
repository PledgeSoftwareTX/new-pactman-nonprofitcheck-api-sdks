/** The result of {@link Nonprofits.check}. */
global class SingleCheckResult extends CheckResult {
    /** The organization, or `null` when the API returned no record. */
    global Nonprofit nonprofit { get; private set; }

    public SingleCheckResult(
        Integer checkCount,
        Decimal timeTakenMs,
        List<ApiErrorDetail> errors,
        String requestId,
        Integer status,
        Object raw,
        Nonprofit nonprofit
    ) {
        super(checkCount, timeTakenMs, errors, requestId, status, raw);
        this.nonprofit = nonprofit;
    }
}
