package org.pactman.nonprofitcheckplus.exceptions;

import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import org.pactman.nonprofitcheckplus.models.ApiErrorDetail;

/**
 * The response metadata every API exception carries.
 *
 * <p>Built by the transport and handed to the exception, so an exception knows
 * everything about the response that produced it — including when the body
 * could not be deserialized.
 */
public final class ApiErrorInit {

    private final int status;
    private final String apiMessage;
    private final Integer apiCode;
    private final List<ApiErrorDetail> apiErrors;
    private final String requestId;
    private final Double retryAfterSeconds;
    private final Object raw;
    private final int attempts;

    private ApiErrorInit(Builder builder) {
        this.status = builder.status;
        this.apiMessage = builder.apiMessage;
        this.apiCode = builder.apiCode;
        this.apiErrors = Collections.unmodifiableList(new ArrayList<>(builder.apiErrors));
        this.requestId = builder.requestId;
        this.retryAfterSeconds = builder.retryAfterSeconds;
        this.raw = builder.raw;
        this.attempts = builder.attempts;
    }

    /**
     * Starts building the metadata for a response.
     *
     * @param status the HTTP status code.
     * @return a new builder.
     */
    public static Builder builder(int status) {
        return new Builder(status);
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
     * {@code message} from the Pactman response envelope, when present.
     *
     * @return the message, or {@code null}.
     */
    public String apiMessage() {
        return apiMessage;
    }

    /**
     * {@code code} from the Pactman response envelope, when present.
     *
     * @return the code, or {@code null}.
     */
    public Integer apiCode() {
        return apiCode;
    }

    /**
     * {@code errors} from the Pactman response envelope, normalized to a list.
     *
     * @return the details. Empty when the API reported none.
     */
    public List<ApiErrorDetail> apiErrors() {
        return apiErrors;
    }

    /**
     * Correlation identifier from the response headers, when present.
     *
     * @return the request id, or {@code null}.
     */
    public String requestId() {
        return requestId;
    }

    /**
     * {@code Retry-After} in seconds, when the server supplied a valid value.
     *
     * @return the delay in seconds, or {@code null}.
     */
    public Double retryAfterSeconds() {
        return retryAfterSeconds;
    }

    /**
     * The parsed response body, or the raw text when it was not JSON.
     *
     * @return the body, or {@code null} when the response had none.
     */
    public Object raw() {
        return raw;
    }

    /**
     * How many attempts were made before this error was surfaced.
     *
     * @return the attempt count, counting the first attempt as one.
     */
    public int attempts() {
        return attempts;
    }

    /** Collects the metadata for one failed response. */
    public static final class Builder {
        private final int status;
        private String apiMessage;
        private Integer apiCode;
        private List<ApiErrorDetail> apiErrors = Collections.emptyList();
        private String requestId;
        private Double retryAfterSeconds;
        private Object raw;
        private int attempts = 1;

        private Builder(int status) {
            this.status = status;
        }

        /**
         * Sets the envelope's message.
         *
         * @param value the message, or {@code null}.
         * @return this builder.
         */
        public Builder apiMessage(String value) {
            this.apiMessage = value;
            return this;
        }

        /**
         * Sets the envelope's code.
         *
         * @param value the code, or {@code null}.
         * @return this builder.
         */
        public Builder apiCode(Integer value) {
            this.apiCode = value;
            return this;
        }

        /**
         * Sets the envelope's item-level errors.
         *
         * @param value the details, or {@code null} for none.
         * @return this builder.
         */
        public Builder apiErrors(List<ApiErrorDetail> value) {
            this.apiErrors = value == null ? Collections.<ApiErrorDetail>emptyList() : value;
            return this;
        }

        /**
         * Sets the correlation identifier from the response headers.
         *
         * @param value the request id, or {@code null}.
         * @return this builder.
         */
        public Builder requestId(String value) {
            this.requestId = value;
            return this;
        }

        /**
         * Sets the server's {@code Retry-After}, in seconds.
         *
         * @param value the delay, or {@code null} when the server sent none.
         * @return this builder.
         */
        public Builder retryAfterSeconds(Double value) {
            this.retryAfterSeconds = value;
            return this;
        }

        /**
         * Sets the response body.
         *
         * @param value the parsed body, or the raw text when it was not JSON.
         * @return this builder.
         */
        public Builder raw(Object value) {
            this.raw = value;
            return this;
        }

        /**
         * Sets how many attempts were made.
         *
         * @param value the attempt count.
         * @return this builder.
         */
        public Builder attempts(int value) {
            this.attempts = value;
            return this;
        }

        /**
         * Builds the metadata.
         *
         * @return an immutable snapshot.
         */
        public ApiErrorInit build() {
            return new ApiErrorInit(this);
        }
    }
}
