package org.pactman.nonprofitcheckplus.http;

import org.pactman.nonprofitcheckplus.models.ResponseBody;

/** A parsed HTTP response plus the metadata callers need. */
public final class TransportResponse {

    private final int status;
    private final String requestId;
    private final ResponseBody body;
    private final int attempts;

    /**
     * Creates the response.
     *
     * @param status    the HTTP status code.
     * @param requestId the correlation identifier from the headers, or {@code null}.
     * @param body      the parsed envelope.
     * @param attempts  how many attempts it took.
     */
    public TransportResponse(int status, String requestId, ResponseBody body, int attempts) {
        this.status = status;
        this.requestId = requestId;
        this.body = body;
        this.attempts = attempts;
    }

    /**
     * The HTTP status code.
     *
     * @return the status.
     */
    public int status() {
        return status;
    }

    /**
     * The correlation identifier from the response headers.
     *
     * @return the request id, or {@code null} when the server sent none.
     */
    public String requestId() {
        return requestId;
    }

    /**
     * The parsed response envelope.
     *
     * @return the envelope. Never {@code null}; an empty body yields an empty envelope.
     */
    public ResponseBody body() {
        return body;
    }

    /**
     * How many attempts the request took.
     *
     * @return the attempt count, counting the first attempt as one.
     */
    public int attempts() {
        return attempts;
    }
}
