using System.Collections.Generic;
using System.Text.Json;

namespace Pactman.NonprofitCheckPlus.Models
{
    /// <summary>
    /// A nonprofit record as returned by the US nonprofit check endpoints.
    /// </summary>
    /// <remarks>
    /// <para>
    /// Source-specific findings are flat on this object, prefixed by source
    /// (<c>pub78_*</c>, <c>bmf_*</c>, <c>ofac_*</c>, and the revocation fields for the
    /// IRS Automatic Revocation of Exemption list). See <see cref="NonprofitCheckPlus.Sources"/>
    /// for grouped views.
    /// </para>
    /// <para>
    /// Every field is optional: the API omits fields it has no data for. Reading one
    /// it did not return yields <see langword="null"/>; ask <see cref="DataObject.Has(string)"/>
    /// to tell the two apart. Fields introduced by a newer API version than this SDK
    /// knows about are readable through <see cref="DataObject.Get(string)"/>.
    /// </para>
    /// <para>
    /// Declared here is what the production API returns. Some deployments serve
    /// additional source fields — the BMF address (<c>bmf_city</c>, <c>bmf_state</c>,
    /// <c>bmf_street_address</c>), <c>bmf_source_pf_filing_req_cd</c>,
    /// <c>bmf_deductability_text</c>, <c>pub78_source_org_type_1..3</c>,
    /// <c>ofac_list_published_date</c> and <c>aroe_list_published_date</c>. They are not
    /// declared because production does not return them; when it does, they stay readable
    /// through <see cref="DataObject.Get(string)"/>, and this package will declare them in
    /// a release of its own.
    /// </para>
    /// </remarks>
    public sealed class Nonprofit : DataObject
    {
        /// <summary>Initializes the record from a decoded JSON object.</summary>
        /// <param name="element">The organization as the API sent it.</param>
        public Nonprofit(JsonElement element)
            : base(element)
        {
        }

        /// <summary>Initializes the record from a set of wire fields.</summary>
        /// <param name="fields">The organization's fields, in document order.</param>
        public Nonprofit(IEnumerable<KeyValuePair<string, JsonElement>> fields)
            : base(fields)
        {
        }

        /// <summary>Public Pactman profile URL for the organization.</summary>
        public string? PactmanOrgUrl => GetString("pactman_org_url");

        /// <summary>When Pactman last modified this organization's record.</summary>
        public string? OrganizationInfoLastModified => GetString("organization_info_last_modified");

        /// <summary>The organization's EIN, as nine digits.</summary>
        public string? Ein => GetString("ein");

        /// <summary>The organization's legal name.</summary>
        public string? OrganizationName => GetString("organization_name");

        /// <summary>The organization's "also known as" name.</summary>
        public string? OrganizationNameAka => GetString("organization_name_aka");

        /// <summary>First line of the organization's address.</summary>
        public string? AddressLine1 => GetString("address_line1");

        /// <summary>Second line of the organization's address.</summary>
        public string? AddressLine2 => GetString("address_line2");

        /// <summary>The organization's city.</summary>
        public string? City => GetString("city");

        /// <summary>The organization's two-letter state code.</summary>
        public string? State => GetString("state");

        /// <summary>The organization's state, spelled out.</summary>
        public string? StateName => GetString("state_name");

        /// <summary>The organization's ZIP code.</summary>
        public string? Zip => GetString("zip");

        /// <summary>The IRS filing requirement code.</summary>
        public string? FilingReqCode => GetString("filing_req_code");

        /// <summary>The Publication 78 note for organizations the IRS treats as churches.</summary>
        public string? Pub78ChurchMessage => GetString("pub78_church_message");

        /// <summary>The organization's name as Publication 78 records it.</summary>
        public string? Pub78OrganizationName => GetString("pub78_organization_name");

        /// <summary>The EIN as Publication 78 records it.</summary>
        public string? Pub78Ein => GetString("pub78_ein");

        /// <summary>Whether the organization appears in Publication 78.</summary>
        public bool? Pub78Verified => GetBoolean("pub78_verified");

        /// <summary>The city as Publication 78 records it.</summary>
        public string? Pub78City => GetString("pub78_city");

        /// <summary>The state as Publication 78 records it.</summary>
        public string? Pub78State => GetString("pub78_state");

        /// <summary>The Publication 78 deductibility indicator.</summary>
        public string? Pub78Indicator => GetString("pub78_indicator");

        /// <summary>The date of the most recent Publication 78 extract behind this record.</summary>
        public string? MostRecentPub78 => GetString("most_recent_pub78");

        /// <summary>The Business Master File note for organizations the IRS treats as churches.</summary>
        public string? BmfChurchMessage => GetString("bmf_church_message");

        /// <summary>The organization's name as the Business Master File records it.</summary>
        public string? BmfOrganizationName => GetString("bmf_organization_name");

        /// <summary>The EIN as the Business Master File records it.</summary>
        public string? BmfEin => GetString("bmf_ein");

        /// <summary>Whether the organization appears in the Business Master File.</summary>
        public bool? BmfStatus => GetBoolean("bmf_status");

        /// <summary>The IRC subsection under which the organization is exempt.</summary>
        public string? BmfSubsection => GetString("bmf_subsection");

        /// <summary>The date of the most recent Business Master File extract behind this record.</summary>
        public string? MostRecentBmf => GetString("most_recent_bmf");

        /// <summary>The subsection, spelled out.</summary>
        public string? SubsectionDescription => GetString("subsection_description");

        /// <summary>The IRS foundation code.</summary>
        public string? FoundationCode => GetString("foundation_code");

        /// <summary>The foundation code, spelled out.</summary>
        public string? FoundationCodeDescription => GetString("foundation_code_description");

        /// <summary>The IRS foundation type code.</summary>
        public string? FoundationTypeCode => GetString("foundation_type_code");

        /// <summary>The foundation type, spelled out.</summary>
        public string? FoundationTypeDescription => GetString("foundation_type_description");

        /// <summary>The organization's 509(a) status.</summary>
        public string? Foundation509aStatus => GetString("foundation_509a_status");

        /// <summary>The month of the IRS ruling.</summary>
        public string? RulingMonth => GetString("ruling_month");

        /// <summary>The year of the IRS ruling.</summary>
        public string? RulingYear => GetString("ruling_year");

        /// <summary>The group exemption number, when the organization holds one.</summary>
        public string? GroupExemption => GetString("group_exemption");

        /// <summary>The IRS exempt status code.</summary>
        public string? ExemptStatusCode => GetString("exempt_status_code");

        /// <summary>
        /// The OFAC Specially Designated Nationals finding.
        /// </summary>
        /// <remarks>
        /// This is prose, not a flag. The API does not currently return a boolean match
        /// indicator, and this SDK does not invent one by matching on the wording.
        /// </remarks>
        public string? OfacStatus => GetString("ofac_status");

        /// <summary>The IRS automatic revocation code, when the exemption was revoked.</summary>
        public string? RevocationCode => GetString("revocation_code");

        /// <summary>The date the exemption was automatically revoked.</summary>
        public string? RevocationDate => GetString("revocation_date");

        /// <summary>The date the exemption was reinstated, when it was.</summary>
        public string? ReinstatementDate => GetString("reinstatement_date");

        /// <summary>True when the IRS Business Master File and Publication 78 records disagree.</summary>
        public bool? IrsBmfPub78Conflict => GetBoolean("irs_bmf_pub78_conflict");

        /// <summary>The date Pactman compiled this report.</summary>
        public string? ReportDate => GetString("report_date");

        /// <summary>
        /// The Publication 78 deductibility entries, as the API sent them.
        /// </summary>
        /// <remarks>
        /// <para>
        /// Returns an empty list when the field was absent or null, so it is always safe
        /// to enumerate; ask <c>Has("organization_types")</c> when the difference matters.
        /// </para>
        /// <para>
        /// The API can also send a null in the list, for a Publication 78 row it cannot
        /// resolve. Those are dropped rather than handed on, so every entry this returns
        /// is a real object and the positions are renumbered from zero — read
        /// <c>Get("organization_types")</c> when the gaps themselves matter.
        /// </para>
        /// </remarks>
        public IReadOnlyList<OrganizationType> OrganizationTypes =>
            OrganizationType.ListFrom(GetElement("organization_types"));
    }
}
