package org.pactman.nonprofitcheckplus.devtools;

/**
 * Named EINs the examples refer to, so no example hard-codes a bare number.
 *
 * <p>These are illustrative and are not real organizations.
 */
public final class FixtureEins {

    /** A 501(c)(3) public charity with every source returned and nothing adverse. */
    public static final String PUBLIC_CHARITY = "411787097";

    /** A second clean organization, for bulk examples. */
    public static final String PUBLIC_CHARITY_SECOND = "996589560";

    /** A 501(c)(3) private foundation — different foundation and filing codes. */
    public static final String PRIVATE_FOUNDATION = "042103594";

    /** A record with most optional identity fields returned as null. */
    public static final String SPARSE_IDENTITY = "060646700";

    /** Address fields that are present but disagree with each other. */
    public static final String INCONSISTENT_ADDRESS = "311580204";

    /** Every source date is old, for the freshness and re-review examples. */
    public static final String STALE_DATA = "362167048";

    /** Listed in the IRS Automatic Revocation of Exemption data, not reinstated. */
    public static final String REVOKED = "237112796";

    /** Revoked and subsequently reinstated — both dates present. */
    public static final String REINSTATED = "133039601";

    /** A possible OFAC SDN match. */
    public static final String OFAC_MATCH = "954367818";

    /** OFAC screening returned no value for this organization. */
    public static final String OFAC_UNAVAILABLE = "061553389";

    /** BMF and Publication 78 disagree; {@code irs_bmf_pub78_conflict} is true. */
    public static final String CONFLICTED = "521693387";

    /** Carries fields and an enum value this SDK version does not know about. */
    public static final String FUTURE_FIELDS = "237324370";

    /** Production's shape plus the source fields only newer deployments return. */
    public static final String PENDING_SOURCE_FIELDS = "046001341";

    /** Well-formed, but no record exists. */
    public static final String NO_RECORD = "999999999";

    /** Always answers HTTP 429 with {@code Retry-After: 1}. */
    public static final String CONTROL_RATE_LIMITED = "900000429";

    /** Answers HTTP 503 twice, then succeeds. */
    public static final String CONTROL_TRANSIENT_FAILURE = "900000503";

    /** Holds the response open, so a short timeout expires. */
    public static final String CONTROL_SLOW = "900000408";

    private FixtureEins() {
    }
}
