package org.pactman.nonprofitcheckplus;

/** The API's paths and limits, declared once. */
public final class Endpoints {

    /**
     * Path of the single-check endpoint.
     *
     * <p>{@code {ein}} is replaced with a normalized EIN.
     */
    public static final String SINGLE_CHECK_PATH = "/api/entities/nonprofitcheck/v1/us/ein/{ein}";

    /** Path of the bulk-check endpoint. */
    public static final String BULK_CHECK_PATH = "/api/entities/nonprofitcheckbulk/v1/us/eins";

    /**
     * Maximum number of EINs the API accepts in one bulk request.
     *
     * <p>This mirrors the server-side limit. It is declared once, here.
     */
    public static final int MAX_BULK_EINS = 50;

    private Endpoints() {
    }
}
