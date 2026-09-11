package org.pactman.nonprofitcheckplus.support;

import java.net.URI;
import java.net.http.HttpHeaders;

/** One request {@link StubExchange} was asked to send. */
public final class RecordedRequest {

    private final URI uri;
    private final String method;
    private final HttpHeaders headers;
    private final String body;

    RecordedRequest(URI uri, String method, HttpHeaders headers, String body) {
        this.uri = uri;
        this.method = method;
        this.headers = headers;
        this.body = body;
    }

    /**
     * The URL the request was sent to.
     *
     * @return the URI.
     */
    public URI uri() {
        return uri;
    }

    /**
     * The HTTP method.
     *
     * @return the method.
     */
    public String method() {
        return method;
    }

    /**
     * One header's value.
     *
     * @param name the header name, case-insensitive.
     * @return the first value, or {@code null} when the header was not sent.
     */
    public String header(String name) {
        return headers.firstValue(name).orElse(null);
    }

    /**
     * The request body.
     *
     * @return the body, or {@code null} when the request had none.
     */
    public String body() {
        return body;
    }
}
