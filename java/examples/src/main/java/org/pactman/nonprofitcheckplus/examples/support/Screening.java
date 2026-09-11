package org.pactman.nonprofitcheckplus.examples.support;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.List;
import java.util.Locale;
import org.pactman.nonprofitcheckplus.Sources;
import org.pactman.nonprofitcheckplus.devtools.ApiDate;
import org.pactman.nonprofitcheckplus.models.AroeSource;
import org.pactman.nonprofitcheckplus.models.BmfSource;
import org.pactman.nonprofitcheckplus.models.Nonprofit;
import org.pactman.nonprofitcheckplus.models.OfacSource;
import org.pactman.nonprofitcheckplus.models.Pub78Source;

/**
 * Shared screening helpers for the workflow examples.
 *
 * <p>These functions gather what the API said into one place. They do not decide
 * anything: there is no {@code approved}, no {@code eligible}, no {@code safe}.
 * Each workflow applies its own policy to this evidence, and the policies differ
 * on purpose — a donation platform, a DAF and a payout gate reach different
 * conclusions from identical data, and all three are right for their own
 * obligations.
 */
public final class Screening {

    /** What the OFAC field said. {@link #UNAVAILABLE} is never a pass. */
    public enum OfacState {
        /** The API returned no OFAC data at all for this organization. */
        UNAVAILABLE,
        /** The API returned the field, with no value in it. */
        NULL,
        /** The wording names a possible SDN match. */
        MATCH,
        /** The wording says the organization was not on the list. */
        NO_MATCH,
        /** The API said something this reader does not recognize. */
        UNRECOGNIZED
    }

    private Screening() {
    }

    /**
     * Classifies the OFAC field.
     *
     * <p>Reading prose is a last resort, and it is done here — in an example, in
     * the caller's own code — rather than in the SDK, precisely because the
     * wording can change. {@link OfacState#UNRECOGNIZED} is the outcome when it
     * does, and a workflow should route that to a person rather than treat it as
     * a pass.
     *
     * @param nonprofit the organization.
     * @return what the OFAC field said.
     */
    public static OfacState ofacState(Nonprofit nonprofit) {
        OfacSource ofac = Sources.ofac(nonprofit);

        if (ofac == null) {
            return OfacState.UNAVAILABLE;
        }

        String status = ofac.getStatus();

        if (status == null) {
            return OfacState.NULL;
        }

        String text = status.toUpperCase(Locale.ROOT);

        if (text.contains("UID:")) {
            return OfacState.MATCH;
        }

        return text.contains("NOT INCLUDED") ? OfacState.NO_MATCH : OfacState.UNRECOGNIZED;
    }

    /**
     * The age in days of the oldest source date on the record.
     *
     * @param nonprofit the organization.
     * @return the age, or {@code null} when no source date could be read.
     */
    public static Long oldestSourceAgeDays(Nonprofit nonprofit) {
        Long oldest = null;

        for (String value : Arrays.asList(
                nonprofit.getMostRecentBmf(),
                nonprofit.getMostRecentPub78(),
                nonprofit.getOrganizationInfoLastModified())) {
            Long age = ApiDate.ageInDays(value);

            if (age != null && (oldest == null || age > oldest)) {
                oldest = age;
            }
        }

        return oldest;
    }

    /**
     * Whether the record shows an automatic revocation that was never reinstated.
     *
     * @param nonprofit the organization.
     * @return true only when a revocation date is present and no reinstatement is.
     */
    public static boolean revokedAndNotReinstated(Nonprofit nonprofit) {
        AroeSource aroe = Sources.aroe(nonprofit);

        return aroe != null
                && aroe.getRevocationDate() != null
                && aroe.getReinstatementDate() == null;
    }

    /**
     * Everything on the record a reviewer would want to see, as plain sentences.
     *
     * <p>Deliberately not scored, ranked or reduced to a flag. Two workflows can
     * read the same list and route it differently, which is the point.
     *
     * @param nonprofit the organization.
     * @return the findings, in source order.
     */
    public static List<String> findings(Nonprofit nonprofit) {
        List<String> findings = new ArrayList<>();

        Pub78Source pub78 = Sources.pub78(nonprofit);
        BmfSource bmf = Sources.bmf(nonprofit);
        AroeSource aroe = Sources.aroe(nonprofit);

        if (pub78 == null) {
            findings.add("Publication 78: no data returned");
        } else if (!Boolean.TRUE.equals(pub78.getVerified())) {
            findings.add("Publication 78: not listed (pub78_verified is "
                    + Output.render(pub78.getVerified()) + ")");
        }

        if (bmf == null) {
            findings.add("Business Master File: no data returned");
        } else if (!Boolean.TRUE.equals(bmf.getStatus())) {
            findings.add("Business Master File: not exempt (bmf_status is "
                    + Output.render(bmf.getStatus()) + ")");
        }

        if (Boolean.TRUE.equals(nonprofit.getIrsBmfPub78Conflict())) {
            findings.add("The API flagged a disagreement between the BMF and Publication 78");
        }

        if (aroe != null && aroe.getRevocationDate() != null) {
            findings.add(aroe.getReinstatementDate() == null
                    ? "Exemption automatically revoked on " + aroe.getRevocationDate()
                            + ", with no reinstatement date"
                    : "Exemption revoked on " + aroe.getRevocationDate() + " and reinstated on "
                            + aroe.getReinstatementDate());
        }

        switch (ofacState(nonprofit)) {
            case MATCH:
                findings.add("OFAC: the API reported a possible SDN match");
                break;
            case UNAVAILABLE:
                findings.add("OFAC: no data returned — absence is not a no-match");
                break;
            case NULL:
                findings.add("OFAC: the field was returned with no value");
                break;
            case UNRECOGNIZED:
                findings.add("OFAC: wording this reader does not recognize — read it yourself");
                break;
            default:
                break;
        }

        return Collections.unmodifiableList(findings);
    }
}
