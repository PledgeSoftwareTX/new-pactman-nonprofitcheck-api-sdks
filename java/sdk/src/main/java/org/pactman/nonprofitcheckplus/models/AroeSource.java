package org.pactman.nonprofitcheckplus.models;

import java.util.Map;

/** IRS Automatic Revocation of Exemption findings. */
public final class AroeSource extends SourceView {

    /**
     * Initializes the view over the projected fields.
     *
     * @param fields the fields copied from the organization.
     */
    public AroeSource(Map<String, Object> fields) {
        super(fields);
    }

    /**
     * The IRS automatic revocation code, when the exemption was revoked.
     *
     * @return the code, or {@code null} when the API returned none.
     */
    public String getRevocationCode() {
        return getString("revocation_code");
    }

    /**
     * The date the exemption was automatically revoked.
     *
     * @return the date as the API formats it, or {@code null}.
     */
    public String getRevocationDate() {
        return getString("revocation_date");
    }

    /**
     * The date the exemption was reinstated, when it was.
     *
     * @return the date as the API formats it, or {@code null}.
     */
    public String getReinstatementDate() {
        return getString("reinstatement_date");
    }
}
