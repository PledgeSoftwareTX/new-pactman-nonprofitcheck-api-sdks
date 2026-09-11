package org.pactman.nonprofitcheckplus.config;

/**
 * Per-request options for
 * {@link org.pactman.nonprofitcheckplus.NonprofitsResource#checkBulk(java.util.List, BulkRequestOptions)}.
 */
public final class BulkRequestOptions extends RequestOptions {

    private boolean dedupe;

    /** Creates options that override nothing. */
    public BulkRequestOptions() {
    }

    /**
     * Removes duplicate EINs before sending, keeping first-seen order.
     *
     * <p>Off by default: duplicates are sent exactly as supplied, because each
     * one consumes quota and silently dropping them would misreport what was
     * checked.
     *
     * @param value whether to remove duplicates.
     * @return these options.
     */
    public BulkRequestOptions dedupe(boolean value) {
        this.dedupe = value;
        return this;
    }

    /**
     * Whether duplicate EINs are removed before sending.
     *
     * @return whether deduplication is on.
     */
    public boolean dedupe() {
        return dedupe;
    }

    @Override
    public BulkRequestOptions timeoutMs(long value) {
        super.timeoutMs(value);
        return this;
    }

    @Override
    public BulkRequestOptions retry(RetryOptions value) {
        super.retry(value);
        return this;
    }

    @Override
    public BulkRequestOptions header(String name, String value) {
        super.header(name, value);
        return this;
    }
}
