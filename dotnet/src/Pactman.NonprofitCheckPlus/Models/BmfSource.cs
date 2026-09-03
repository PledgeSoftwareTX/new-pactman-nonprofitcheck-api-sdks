using System.Collections.Generic;
using System.Text.Json;

namespace Pactman.NonprofitCheckPlus.Models
{
    /// <summary>IRS Business Master File findings.</summary>
    public sealed class BmfSource : SourceView
    {
        /// <summary>Initializes the view over the projected fields.</summary>
        /// <param name="fields">The fields copied from the organization.</param>
        public BmfSource(IEnumerable<KeyValuePair<string, JsonElement>> fields)
            : base(fields)
        {
        }

        /// <summary>Whether the organization appears in the Business Master File.</summary>
        public bool? Status => GetBoolean("status");

        /// <summary>The organization's name as the Business Master File records it.</summary>
        public string? OrganizationName => GetString("organization_name");

        /// <summary>The EIN as the Business Master File records it.</summary>
        public string? Ein => GetString("ein");

        /// <summary>The note for organizations the IRS treats as churches.</summary>
        public string? ChurchMessage => GetString("church_message");

        /// <summary>The IRC subsection under which the organization is exempt.</summary>
        public string? Subsection => GetString("subsection");

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

        /// <summary>The IRS filing requirement code.</summary>
        public string? FilingReqCode => GetString("filing_req_code");

        /// <summary>The date of the most recent Business Master File extract behind this record.</summary>
        public string? MostRecent => GetString("most_recent");
    }
}
