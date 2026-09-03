using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;

namespace Pactman.NonprofitCheckPlus.Dev;

/// <summary>
/// Fixture organizations for the examples and the mock server.
/// </summary>
/// <remarks>
/// Scenarios like a revoked exemption, an OFAC match, a cross-source conflict or an
/// unknown future field cannot be summoned on demand from the production API. They are
/// declared here once so an example can demonstrate the handling and the mock server can
/// serve the record.
/// <para>
/// Field names and values mirror the shapes documented in the Pactman API reference. The
/// EINs are illustrative and are not real organizations.
/// </para>
/// </remarks>
public static class Fixtures
{
    /// <summary>The two OFAC sentences the API returns. It reports prose, not a boolean.</summary>
    public const string OfacNoMatch =
        "This organization was NOT included in the Office of Foreign Assets "
        + "Control Specially Designated Nationals (SDN) list.";

    /// <summary>The wording the API uses when an organization may be on the SDN list.</summary>
    public const string OfacPossibleMatch =
        "This organization may be included in the Office of Foreign "
        + "Assets Control Specially Designated Nationals(SDN) list. A close match was found with "
        + "the Special Designated National with UID: 41234";

    /// <summary>
    /// Named EINs the examples refer to, so no example hard-codes a bare number.
    /// </summary>
    public static class Eins
    {
        /// <summary>A 501(c)(3) public charity with every source returned and nothing adverse.</summary>
        public const string PublicCharity = "411787097";

        /// <summary>A second clean organization, for bulk examples.</summary>
        public const string PublicCharitySecond = "996589560";

        /// <summary>A 501(c)(3) private foundation — different foundation and filing codes.</summary>
        public const string PrivateFoundation = "042103594";

        /// <summary>A record with most optional identity fields returned as null.</summary>
        public const string SparseIdentity = "060646700";

        /// <summary>Address fields that are present but disagree with each other.</summary>
        public const string InconsistentAddress = "311580204";

        /// <summary>Every source date is old, for the freshness and re-review examples.</summary>
        public const string StaleData = "362167048";

        /// <summary>Listed in the IRS Automatic Revocation of Exemption data, not reinstated.</summary>
        public const string Revoked = "237112796";

        /// <summary>Revoked and subsequently reinstated — both dates present.</summary>
        public const string Reinstated = "133039601";

        /// <summary>A possible OFAC SDN match.</summary>
        public const string OfacMatch = "954367818";

        /// <summary>OFAC screening returned no value for this organization.</summary>
        public const string OfacUnavailable = "061553389";

        /// <summary>BMF and Publication 78 disagree; <c>irs_bmf_pub78_conflict</c> is true.</summary>
        public const string Conflicted = "521693387";

        /// <summary>Carries fields and an enum value this SDK version does not know about.</summary>
        public const string FutureFields = "237324370";

        /// <summary>Production's shape plus the source fields only newer deployments return.</summary>
        public const string PendingSourceFields = "046001341";

        /// <summary>Well-formed, but no record exists.</summary>
        public const string NoRecord = "999999999";
    }

    /// <summary>
    /// EINs the mock server answers with a specific failure, for the error examples.
    /// </summary>
    public static class ControlEins
    {
        /// <summary>Always answers HTTP 429 with <c>Retry-After: 1</c>.</summary>
        public const string RateLimited = "900000429";

        /// <summary>Answers HTTP 503 twice, then succeeds.</summary>
        public const string TransientFailure = "900000503";

        /// <summary>Holds the response open, so a short timeout expires.</summary>
        public const string Slow = "900000408";
    }

    private static JsonObject DeductibilityPublicCharity() => new()
    {
        ["organization_type"] = "Deductions for donations to public charities are generally limited "
            + "to 50 percent of adjusted gross income (AGI). This limit increases to 60% of AGI for "
            + "cash donations. For Non-Cash assets held for more than one year, the limit is 30% of AGI.",
        ["deductibility_limitation"] = "50%",
        ["deductibility_status_description"] = "PC",
    };

    private static JsonObject DeductibilityPrivateFoundation() => new()
    {
        ["organization_type"] = "Deductions for donations to private foundations are generally "
            + "limited to 30 percent of adjusted gross income (AGI). For Non-Cash assets held for "
            + "more than one year, the limit is 20% of AGI.",
        ["deductibility_limitation"] = "30%",
        ["deductibility_status_description"] = "PF",
    };

    /// <summary>
    /// The API formats every date as <c>M/DD/YYYY h:mm:ss AM</c>.
    /// </summary>
    /// <remarks>
    /// Fixture dates are generated relative to today, so the freshness examples stay
    /// meaningful however long after they were written they are run.
    /// </remarks>
    public static string ApiDate(int daysAgo)
    {
        var date = DateTime.Now.AddDays(-daysAgo);

        return date.ToString("M/dd/yyyy", CultureInfo.InvariantCulture)
            + " " + date.ToString("h:mm:ss tt", CultureInfo.InvariantCulture).ToUpperInvariant();
    }

    /// <summary>True when the mock server has a record for this EIN.</summary>
    public static bool Has(string ein) => Builders.ContainsKey(ein);

    /// <summary>Every EIN the mock server has a record for.</summary>
    public static IReadOnlyCollection<string> KnownEins => Builders.Keys.ToArray();

    /// <summary>
    /// A record for <paramref name="ein"/>. Each call builds a fresh object, so an example
    /// that mutates one cannot affect a later call.
    /// </summary>
    public static JsonObject Organization(string ein) => Builders[ein]();

    /// <summary>
    /// Every field this package predicts on an organization.
    /// </summary>
    /// <remarks>
    /// Read from the contract shipped inside the library rather than from a fixture, so
    /// that what the SDK claims to know is stated in one place. A fixture is an example of
    /// a record; the contract is the promise, and the promise is what drift is measured
    /// against. See EX-25: a field outside this set is newer than this SDK, which is not
    /// an error, but is worth knowing about.
    /// </remarks>
    public static IReadOnlyList<string> KnownNonprofitFields() =>
        ResponseContract().GetProperty("nonprofit").EnumerateObject().Select(field => field.Name).ToList();

    /// <summary>The response contract, read from the resource embedded in the shipped library.</summary>
    public static JsonElement ResponseContract() => EmbeddedJson("response-contract.json");

    /// <summary>The recorded production baseline, read from the resource embedded in the shipped library.</summary>
    public static JsonElement ResponseBaseline() => EmbeddedJson("response-baseline.json");

    private static JsonElement EmbeddedJson(string name)
    {
        var assembly = typeof(PactmanClient).Assembly;
        var resource = assembly.GetManifestResourceNames()
            .First(candidate => candidate.EndsWith(name, StringComparison.Ordinal));

        using var stream = assembly.GetManifestResourceStream(resource)!;
        using var reader = new StreamReader(stream);

        return JsonSerializer.Deserialize<JsonElement>(reader.ReadToEnd());
    }

    private static readonly IReadOnlyDictionary<string, Func<JsonObject>> Builders =
        new Dictionary<string, Func<JsonObject>>(StringComparer.Ordinal)
        {
            [Eins.PublicCharity] = () => PublicCharity(
                Eins.PublicCharity,
                "Meals Today Example Nonprofit",
                organization =>
                {
                    organization["organization_name_aka"] = "MEALS TODAY E.N";
                    organization["pub78_organization_name"] = "Meals Today Example Nonprofit, Inc.";
                }),

            [Eins.PublicCharitySecond] = () => PublicCharity(
                Eins.PublicCharitySecond,
                "Aborjaily Example Nonprofit",
                organization =>
                {
                    organization["organization_name_aka"] = "ABORJAILY E.N";
                    organization["city"] = "SPRINGFIELD";
                    organization["pub78_city"] = "Springfield";
                    organization["zip"] = "01103-1420";
                    organization["address_line1"] = "19 HAMPDEN ST";
                    organization["address_line2"] = null;
                }),

            [Eins.PrivateFoundation] = () => PublicCharity(
                Eins.PrivateFoundation,
                "Hartwell Family Example Foundation",
                organization =>
                {
                    organization["organization_name_aka"] = null;

                    // A private foundation files a 990-PF, so it carries no general
                    // 990 filing requirement.
                    organization["filing_req_code"] = "00";
                    organization["organization_types"] = new JsonArray { DeductibilityPrivateFoundation() };
                    organization["subsection_description"] = "501(c)(3) Private Foundation";
                    organization["foundation_code"] = "04";
                    organization["foundation_code_description"] = "Private non-operating foundation";
                    organization["foundation_type_code"] = "pf";
                    organization["foundation_type_description"] = "Private non-operating foundation";
                    organization["foundation_509a_status"] = "N/A";
                    organization["ruling_month"] = "11";
                    organization["ruling_year"] = "1998";
                }),

            // Optional identity fields the API had no value for. Null here means "the
            // API returned no value", which is not the same as "this did not match".
            [Eins.SparseIdentity] = () => PublicCharity(
                Eins.SparseIdentity,
                "Quiet Harbor Example Trust",
                organization =>
                {
                    organization["organization_name_aka"] = null;
                    organization["address_line1"] = "PO BOX 118";
                    organization["address_line2"] = null;
                    organization["city"] = "ROCKPORT";
                    organization["state"] = "ME";
                    organization["state_name"] = null;
                    organization["zip"] = null;
                    organization["pub78_city"] = null;
                    organization["pub78_state"] = null;
                    organization["group_exemption"] = null;
                    organization["ruling_month"] = null;
                    organization["ruling_year"] = null;
                },
                // No OFAC key at all: the source was not reported for this
                // organization, which is not the same as a null status or a
                // no-match result.
                "ofac_status"),

            // Every address component is present, and they contradict one another: the
            // state code says Massachusetts, the state name and the ZIP say Maine, and
            // address_line2 holds a placeholder. Transcription damage of this kind
            // survives any check that only asks whether a field came back non-null.
            [Eins.InconsistentAddress] = () => PublicCharity(
                Eins.InconsistentAddress,
                "Harbor Light Example Alliance",
                organization =>
                {
                    organization["organization_name_aka"] = null;
                    organization["address_line1"] = "12 SEA STREET";
                    organization["address_line2"] = "N/A";
                    organization["city"] = "ROCKPORT";
                    organization["state"] = "MA";
                    organization["state_name"] = "Maine";
                    organization["zip"] = "04856";
                    organization["pub78_city"] = "Rockport";
                    organization["pub78_state"] = "MA";
                }),

            // Nothing adverse, but every source is well out of date. A workflow with a
            // re-review rule should notice this even though the findings look clean.
            [Eins.StaleData] = () => PublicCharity(
                Eins.StaleData,
                "Long Quiet Example Foundation",
                organization =>
                {
                    organization["organization_info_last_modified"] = ApiDate(700);
                    organization["most_recent_pub78"] = ApiDate(640);
                    organization["most_recent_bmf"] = ApiDate(610);
                }),

            [Eins.Revoked] = () => PublicCharity(
                Eins.Revoked,
                "Lapsed Filings Example Society",
                organization =>
                {
                    organization["organization_name_aka"] = null;
                    organization["pub78_verified"] = false;
                    organization["pub78_indicator"] = null;
                    organization["organization_types"] = null;
                    organization["bmf_status"] = false;
                    organization["subsection_description"] = "501(c)(3) Public Charity";
                    organization["exempt_status_code"] = "25";
                    organization["revocation_code"] = "01";
                    organization["revocation_date"] = ApiDate(1260);
                    organization["reinstatement_date"] = null;
                }),

            [Eins.Reinstated] = () => PublicCharity(
                Eins.Reinstated,
                "Second Chance Example Alliance",
                organization =>
                {
                    organization["organization_name_aka"] = "SECOND CHANCE E.A";
                    organization["revocation_code"] = "01";
                    organization["revocation_date"] = ApiDate(1260);
                    organization["reinstatement_date"] = ApiDate(520);
                }),

            [Eins.OfacMatch] = () => PublicCharity(
                Eins.OfacMatch,
                "Overseas Relief Example Fund",
                organization =>
                {
                    organization["organization_name_aka"] = "OVERSEAS RELIEF E.F";
                    organization["ofac_status"] = OfacPossibleMatch;
                }),

            // The API returned nothing for OFAC. Absent is not the same as "no match".
            [Eins.OfacUnavailable] = () => PublicCharity(
                Eins.OfacUnavailable,
                "Riverbend Example Coalition",
                organization =>
                {
                    organization["ofac_status"] = null;
                }),

            // BMF says exempt, Publication 78 does not list the organization, and the
            // API flags the disagreement rather than picking a winner.
            [Eins.Conflicted] = () => PublicCharity(
                Eins.Conflicted,
                "Crosscheck Example Institute",
                organization =>
                {
                    organization["organization_name"] = "CROSSCHECK EXAMPLE INSTITUTE";
                    organization["organization_name_aka"] = null;
                    organization["pub78_verified"] = false;
                    organization["pub78_organization_name"] = null;
                    organization["pub78_city"] = null;
                    organization["pub78_state"] = null;
                    organization["pub78_indicator"] = null;
                    organization["organization_types"] = null;
                    organization["most_recent_pub78"] = ApiDate(26);
                    organization["bmf_organization_name"] = "CROSSCHECK EXAMPLE INST";
                    organization["bmf_status"] = true;
                    organization["irs_bmf_pub78_conflict"] = true;
                }),

            // A response from a newer API version: fields this SDK has never heard of,
            // and an enum value outside the documented set.
            [Eins.FutureFields] = () => PublicCharity(
                Eins.FutureFields,
                "Forward Compatible Example Trust",
                organization =>
                {
                    organization["foundation_type_code"] = "zz";
                    organization["foundation_type_description"] =
                        "A classification added after this SDK was published";

                    var entry = DeductibilityPublicCharity();
                    entry["deductibility_status_description"] = "XX";
                    entry["future_deductibility_note"] = "An unknown member of a known object";
                    organization["organization_types"] = new JsonArray { entry };

                    organization["state_charity_registration_status"] = "ACTIVE";
                    organization["watchlist_screening"] = new JsonObject
                    {
                        ["provider"] = "example",
                        ["matches"] = 0,
                        ["list_published_date"] = ApiDate(5),
                    };
                }),

            // A deployment running ahead of production. Every other fixture is the
            // shape entities.pactman.org returns today; this one adds the ten source
            // fields that are built but not yet released there. This package
            // deliberately does not declare them (see Nonprofit in Models), so they
            // exercise the path that keeps undeclared fields readable through Get()
            // instead of dropping them.
            [Eins.PendingSourceFields] = () => PublicCharity(
                Eins.PendingSourceFields,
                "Ahead Of Production Example Fund",
                organization =>
                {
                    organization["organization_name_aka"] = null;
                    organization["pub78_source_org_type_1"] = "PC";
                    organization["pub78_source_org_type_2"] = null;
                    organization["pub78_source_org_type_3"] = null;
                    organization["bmf_city"] = "WESTFIELD";
                    organization["bmf_state"] = "MA";
                    organization["bmf_street_address"] = "50 LOWELL AVE APT 3B";
                    organization["bmf_source_pf_filing_req_cd"] = "0";
                    organization["bmf_deductability_text"] = "Contributions are deductible";
                    organization["ofac_list_published_date"] = ApiDate(5);
                    organization["aroe_list_published_date"] = ApiDate(12);
                }),
        };

    /// <summary>
    /// A complete, unremarkable public charity. Scenarios override from here.
    /// </summary>
    /// <param name="ein">The organization's EIN.</param>
    /// <param name="name">The organization's name.</param>
    /// <param name="customize">Applied after the defaults, to express one scenario.</param>
    /// <param name="omit">
    /// Keys to delete outright, so the record can express "the API returned no field at
    /// all" as distinct from "the API returned null".
    /// </param>
    private static JsonObject PublicCharity(
        string ein,
        string name,
        Action<JsonObject>? customize = null,
        params string[] omit)
    {
        var organization = new JsonObject
        {
            ["pactman_org_url"] = $"https://pactman.org/profile/nonprofit/{Slug(name)}-{ein[^4..]}",
            ["organization_info_last_modified"] = ApiDate(40),

            ["ein"] = ein,
            ["organization_name"] = name.ToUpperInvariant(),
            ["organization_name_aka"] = null,
            ["address_line1"] = "50 LOWELL AVE",
            ["address_line2"] = "APT 3B",
            ["city"] = "WESTFIELD",
            ["state"] = "MA",
            ["state_name"] = "Massachusetts",
            ["zip"] = "01085-2643",
            ["filing_req_code"] = "01",

            ["pub78_church_message"] = null,
            ["pub78_organization_name"] = name,
            ["pub78_ein"] = ein,
            ["pub78_verified"] = true,
            ["pub78_city"] = "Westfield",
            ["pub78_state"] = "MA",
            ["pub78_indicator"] = "0",
            ["organization_types"] = new JsonArray { DeductibilityPublicCharity() },
            ["most_recent_pub78"] = ApiDate(26),

            ["bmf_church_message"] = null,
            ["bmf_organization_name"] = name.ToUpperInvariant(),
            ["bmf_ein"] = ein,
            ["bmf_status"] = true,
            ["bmf_subsection"] = "03",
            ["most_recent_bmf"] = ApiDate(20),
            ["subsection_description"] = "501(c)(3) Public Charity",
            ["foundation_code"] = "10",
            ["foundation_code_description"] = "Public charity described in section 509(a)(1) or (2)",
            ["foundation_type_code"] = "pc",
            ["foundation_type_description"] = "Public charity described in section 509(a)(1) or (2)",
            ["foundation_509a_status"] = "N/A",
            ["ruling_month"] = "07",
            ["ruling_year"] = "2024",
            ["group_exemption"] = "0000",
            ["exempt_status_code"] = "01",

            ["ofac_status"] = OfacNoMatch,

            ["revocation_code"] = null,
            ["revocation_date"] = null,
            ["reinstatement_date"] = null,

            ["irs_bmf_pub78_conflict"] = false,
            ["report_date"] = ApiDate(0),
        };

        customize?.Invoke(organization);

        foreach (var key in omit)
        {
            organization.Remove(key);
        }

        return organization;
    }

    private static string Slug(string name) =>
        Regex.Replace(name.ToLowerInvariant(), "[^a-z0-9]+", "-").Trim('-');
}
