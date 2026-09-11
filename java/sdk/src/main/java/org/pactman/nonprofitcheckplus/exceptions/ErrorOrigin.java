package org.pactman.nonprofitcheckplus.exceptions;

/** Whether an error was raised locally or derived from an API response. */
public enum ErrorOrigin {

    /** Raised by this SDK before, or instead of, an HTTP exchange. */
    LOCAL("local"),

    /** Derived from a response the API returned. */
    API("api");

    private final String wireName;

    ErrorOrigin(String wireName) {
        this.wireName = wireName;
    }

    /**
     * The origin name the SDKs in every language share.
     *
     * @return {@code local} or {@code api}.
     */
    public String wireName() {
        return wireName;
    }

    @Override
    public String toString() {
        return wireName;
    }
}
