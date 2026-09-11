package org.pactman.nonprofitcheckplus.models;

import java.util.List;
import java.util.Map;

/** The envelope every nonprofit check response is wrapped in. */
public final class ResponseBody extends DataObject {

    /**
     * Initializes the envelope from a decoded JSON object.
     *
     * @param fields the envelope as the API sent it.
     */
    public ResponseBody(Map<String, Object> fields) {
        super(fields);
    }

    /**
     * The envelope's status code, which may differ from the HTTP status.
     *
     * @return the code, or {@code null} when the API returned none.
     */
    public Integer getCode() {
        return getInteger("code");
    }

    /**
     * The envelope's message.
     *
     * @return the message, or {@code null} when the API returned none.
     */
    public String getMessage() {
        return getString("message");
    }

    /**
     * Item-level failures.
     *
     * <p>Present on successful responses too — a bulk request where some EINs
     * were not found returns HTTP 200 with entries here.
     *
     * @return the details. Empty when the API reported none.
     */
    public List<ApiErrorDetail> getErrors() {
        return ApiErrorDetail.listFrom(get("errors"));
    }

    /**
     * The envelope's payload, exactly as it was decoded.
     *
     * <p>An organization is an object, a bulk result is a list, and an empty
     * result is {@code null}. The typed results on
     * {@link org.pactman.nonprofitcheckplus.NonprofitsResource} read this for
     * you; reach for it when you want the shape the server actually sent.
     *
     * @return the payload, or {@code null}.
     */
    public Object getData() {
        return get("data");
    }

    /**
     * Server-side processing time in milliseconds, when reported.
     *
     * @return the duration, or {@code null}.
     */
    public Double getTimeTaken() {
        return getDouble("timeTaken");
    }

    /**
     * Checks the account has consumed so far in the current billing cycle,
     * including this request. It resets when a new cycle begins.
     *
     * <p>This is a running total, not the size of the request you just made. To
     * learn what one request cost, compare this value across two responses.
     *
     * @return the running total, or {@code null} when the API returned none.
     */
    public Integer getNonprofitCheckCount() {
        return getInteger("nonprofit_check_count");
    }
}
