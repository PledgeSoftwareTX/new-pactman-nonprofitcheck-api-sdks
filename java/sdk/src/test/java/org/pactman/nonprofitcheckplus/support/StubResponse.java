package org.pactman.nonprofitcheckplus.support;

import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/** A canned HTTP response for {@link StubExchange} to serve. */
public final class StubResponse {

    private int status = 200;
    private String body;
    private final Map<String, List<String>> headers = new LinkedHashMap<>();

    private StubResponse() {
    }

    /**
     * A 200 carrying a JSON body.
     *
     * @param json the body, already serialized.
     * @return the stub.
     */
    public static StubResponse json(String json) {
        return new StubResponse().body(json).header("content-type", "application/json");
    }

    /**
     * A response with a status and a JSON body.
     *
     * @param status the HTTP status.
     * @param json   the body, already serialized.
     * @return the stub.
     */
    public static StubResponse of(int status, String json) {
        return json(json).status(status);
    }

    /**
     * A response with a status and no body at all.
     *
     * @param status the HTTP status.
     * @return the stub.
     */
    public static StubResponse empty(int status) {
        return new StubResponse().status(status);
    }

    /**
     * Sets the status.
     *
     * @param value the HTTP status.
     * @return this stub.
     */
    public StubResponse status(int value) {
        this.status = value;
        return this;
    }

    /**
     * Sets the raw body, which need not be JSON.
     *
     * @param value the body.
     * @return this stub.
     */
    public StubResponse body(String value) {
        this.body = value;
        return this;
    }

    /**
     * Adds a response header.
     *
     * @param name  the header name.
     * @param value the header value.
     * @return this stub.
     */
    public StubResponse header(String name, String value) {
        headers.computeIfAbsent(name, key -> new ArrayList<>()).add(value);
        return this;
    }

    int statusCode() {
        return status;
    }

    String bodyText() {
        return body == null ? "" : body;
    }

    Map<String, List<String>> headerMap() {
        return headers;
    }
}
