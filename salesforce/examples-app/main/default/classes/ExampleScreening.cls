/**
 * Shared screening helpers for the workflow examples.
 *
 * These gather what the API said into one place. They decide nothing: there is
 * no `approved`, no `eligible`, no `safe`. Each workflow applies its own policy
 * to this evidence, and the policies differ on purpose — a donation platform, a
 * DAF and a payout gate reach different conclusions from identical data, and all
 * three are right for their own obligations.
 */
@IsTest
public class ExampleScreening {
    /** The API returned no OFAC data at all for this organization. */
    public static final String OFAC_UNAVAILABLE = 'UNAVAILABLE';

    /** The API returned the field, with no value in it. */
    public static final String OFAC_NULL = 'NULL';

    /** The wording names a possible SDN match. */
    public static final String OFAC_MATCH = 'MATCH';

    /** The wording says the organization was not on the list. */
    public static final String OFAC_NO_MATCH = 'NO_MATCH';

    /** The API said something this reader does not recognize. */
    public static final String OFAC_UNRECOGNIZED = 'UNRECOGNIZED';

    /**
     * Classifies the OFAC field.
     *
     * Reading prose is a last resort, and it is done here — in an example, in
     * the caller's own code — rather than in the SDK, precisely because the
     * wording can change. {@link OFAC_UNRECOGNIZED} is the outcome when it
     * does, and a workflow should route that to a person rather than treat it
     * as a pass.
     */
    public static String ofacState(Nonprofit nonprofit) {
        OfacSource ofac = Sources.getOfac(nonprofit);

        if (ofac == null) {
            return OFAC_UNAVAILABLE;
        }

        if (ofac.status == null) {
            return OFAC_NULL;
        }

        String text = ofac.status.toUpperCase();

        if (text.contains('UID:')) {
            return OFAC_MATCH;
        }

        return text.contains('NOT INCLUDED') ? OFAC_NO_MATCH : OFAC_UNRECOGNIZED;
    }

    /**
     * The age in days of the oldest source date on the record, or `null` when
     * no source date could be read.
     */
    public static Integer oldestSourceAgeDays(Nonprofit nonprofit) {
        Integer oldest = null;

        List<String> dates = new List<String>{
            nonprofit.most_recent_bmf,
            nonprofit.most_recent_pub78,
            nonprofit.organization_info_last_modified
        };

        for (String value : dates) {
            Integer age = ExampleDates.ageInDays(value);

            if (age != null && (oldest == null || age > oldest)) {
                oldest = age;
            }
        }

        return oldest;
    }

    /**
     * True only when a revocation date is present and no reinstatement date is.
     */
    public static Boolean revokedAndNotReinstated(Nonprofit nonprofit) {
        AroeSource aroe = Sources.getAroe(nonprofit);

        return aroe != null && aroe.revocation_date != null && aroe.reinstatement_date == null;
    }

    /**
     * Everything on the record a reviewer would want to see, as plain sentences.
     *
     * Deliberately not scored, ranked or reduced to a flag. Two workflows can
     * read the same list and route it differently, which is the point.
     */
    public static List<String> findings(Nonprofit nonprofit) {
        List<String> findings = new List<String>();

        Pub78Source pub78 = Sources.getPub78(nonprofit);
        BmfSource bmf = Sources.getBmf(nonprofit);
        AroeSource aroe = Sources.getAroe(nonprofit);

        if (pub78 == null) {
            findings.add('Publication 78: no data returned');
        } else if (pub78.verified != true) {
            findings.add(
                'Publication 78: not listed (pub78_verified is ' +
                    ExampleOutput.render(pub78.verified) + ')'
            );
        }

        if (bmf == null) {
            findings.add('Business Master File: no data returned');
        } else if (bmf.status != true) {
            findings.add(
                'Business Master File: not exempt (bmf_status is ' +
                    ExampleOutput.render(bmf.status) + ')'
            );
        }

        if (nonprofit.irs_bmf_pub78_conflict == true) {
            findings.add('The API flagged a disagreement between the BMF and Publication 78');
        }

        if (aroe != null && aroe.revocation_date != null) {
            findings.add(
                aroe.reinstatement_date == null
                    ? 'Exemption automatically revoked on ' + aroe.revocation_date +
                          ', with no reinstatement date'
                    : 'Exemption revoked on ' + aroe.revocation_date +
                          ' and reinstated on ' + aroe.reinstatement_date
            );
        }

        String ofac = ofacState(nonprofit);

        if (ofac == OFAC_MATCH) {
            findings.add('OFAC: the API reported a possible SDN match');
        } else if (ofac == OFAC_UNAVAILABLE) {
            findings.add('OFAC: no data returned - absence is not a no-match');
        } else if (ofac == OFAC_NULL) {
            findings.add('OFAC: the field was returned with no value');
        } else if (ofac == OFAC_UNRECOGNIZED) {
            findings.add('OFAC: wording this reader does not recognize - read it yourself');
        }

        return findings;
    }

    /**
     * The matched organizations from a bulk result, keyed by EIN.
     *
     * `BulkCheckResult.byEin()` already does this; the workflows call it
     * through here so that the reason is stated once: the API matches by set
     * membership, so the response order does not follow the request order and
     * pairing positionally would attribute one organization's findings to
     * another.
     */
    public static Map<String, Nonprofit> byEin(BulkCheckResult result) {
        return result.byEin();
    }
}
