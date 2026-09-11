package org.pactman.nonprofitcheckplus.exceptions;

import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import org.pactman.nonprofitcheckplus.models.ApiErrorDetail;

/**
 * An error returned by the Pactman API.
 *
 * <p>Thrown directly when the status maps to no more specific subclass;
 * response metadata is preserved even when the body could not be deserialized.
 */
public class PactmanApiException extends PactmanException {

    private static final long serialVersionUID = 1L;

    /** @serial the HTTP status of the response. */
    private final int status;

    /** @serial the envelope's message, or {@code null}. */
    private final String apiMessage;

    /** @serial the envelope's code, or {@code null}. */
    private final Integer apiCode;

    /** @serial the correlation identifier from the headers, or {@code null}. */
    private final String requestId;

    /** @serial the server's {@code Retry-After} in seconds, or {@code null}. */
    private final Double retryAfterSeconds;

    /** @serial how many attempts were made. */
    private final int attempts;

    /**
     * The item-level failures. Not serialized: a decoded response body is
     * arbitrary JSON, and forcing the model graph to be {@link java.io.Serializable}
     * to carry it would be a larger promise than this field is worth. A
     * deserialized exception reports an empty list.
     */
    private final transient List<ApiErrorDetail> apiErrors;

    /**
     * The response body. Not serialized, for the same reason as
     * {@link #apiErrors}; a deserialized exception reports {@code null}.
     */
    private final transient Object raw;

    /**
     * Creates the exception in the general {@link ErrorCategory#API} category.
     *
     * @param message the message to surface.
     * @param init    the response metadata.
     */
    public PactmanApiException(String message, ApiErrorInit init) {
        this(message, init, ErrorCategory.API);
    }

    /**
     * Creates the exception in a specific category.
     *
     * @param message  the message to surface.
     * @param init     the response metadata.
     * @param category the category this status maps to.
     */
    protected PactmanApiException(String message, ApiErrorInit init, ErrorCategory category) {
        super(message, category, ErrorOrigin.API, null);
        this.status = init.status();
        this.apiMessage = init.apiMessage();
        this.apiCode = init.apiCode();
        this.requestId = init.requestId();
        this.retryAfterSeconds = init.retryAfterSeconds();
        this.attempts = init.attempts();
        this.apiErrors = init.apiErrors();
        this.raw = init.raw();
    }

    /**
     * Builds the exception subclass that matches an HTTP status code.
     *
     * @param init the response metadata, carrying the status.
     * @return the most specific exception for the status.
     */
    public static PactmanApiException fromStatus(ApiErrorInit init) {
        String apiMessage = init.apiMessage();
        String message = apiMessage != null && !apiMessage.trim().isEmpty()
                ? apiMessage.trim()
                : defaultMessageForStatus(init.status());

        switch (init.status()) {
            case 400:
                return new PactmanBadRequestException(message, init);
            case 401:
                return new PactmanAuthenticationException(message, init);
            case 403:
                return new PactmanAuthorizationException(message, init);
            case 404:
                return new PactmanNotFoundException(message, init);
            case 429:
                return new PactmanRateLimitException(message, init);
            default:
                if (init.status() >= 500) {
                    return new PactmanServerException(message, init);
                }

                return new PactmanApiException(message, init);
        }
    }

    private static String defaultMessageForStatus(int status) {
        switch (status) {
            case 400:
                return "The Pactman API rejected the request.";
            case 401:
                return "The Pactman API key was rejected.";
            case 403:
                return "This Pactman API key is not permitted to access that resource.";
            case 404:
                return "No matching record was found.";
            case 429:
                return "The Pactman API rate limit was exceeded.";
            default:
                return status >= 500
                        ? "The Pactman API returned a server error (HTTP " + status + ")."
                        : "The Pactman API returned an unexpected response (HTTP " + status + ").";
        }
    }

    /**
     * The HTTP status code of the response.
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
     * <p>This can differ from the HTTP status.
     *
     * @return the code, or {@code null}.
     */
    public Integer apiCode() {
        return apiCode;
    }

    /**
     * Item-level failures the API reported.
     *
     * @return the details. Empty when the API reported none.
     */
    public List<ApiErrorDetail> apiErrors() {
        return apiErrors == null ? java.util.Collections.<ApiErrorDetail>emptyList() : apiErrors;
    }

    /**
     * Correlation identifier from the response headers.
     *
     * <p>Quote it when reporting a problem to Pactman support.
     *
     * @return the request id, or {@code null} when the server sent none.
     */
    public String requestId() {
        return requestId;
    }

    /**
     * The server's {@code Retry-After}, in seconds.
     *
     * @return the delay, or {@code null} when the server sent none.
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

    @Override
    public Map<String, Object> toMap() {
        Map<String, Object> fields = super.toMap();
        fields.put("status", status());
        fields.put("apiMessage", apiMessage());
        fields.put("apiCode", apiCode());

        List<Map<String, Object>> details = new ArrayList<>(apiErrors().size());

        for (ApiErrorDetail detail : apiErrors()) {
            details.add(detail.toMap());
        }

        fields.put("apiErrors", details);
        fields.put("requestId", requestId());
        fields.put("retryAfterSeconds", retryAfterSeconds());
        fields.put("attempts", attempts());

        return fields;
    }
}
