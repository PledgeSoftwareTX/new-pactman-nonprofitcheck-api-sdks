package org.pactman.nonprofitcheckplus.models;

import java.util.Map;

/** OFAC Specially Designated Nationals findings. */
public final class OfacSource extends SourceView {

    /**
     * Initializes the view over the projected fields.
     *
     * @param fields the fields copied from the organization.
     */
    public OfacSource(Map<String, Object> fields) {
        super(fields);
    }

    /**
     * The finding as the API phrases it.
     *
     * <p>This is prose, not a flag; the API does not currently return a boolean
     * match indicator, and this SDK does not invent one by matching on the
     * wording.
     *
     * @return the finding, or {@code null} when the API returned none.
     */
    public String getStatus() {
        return getString("status");
    }
}
