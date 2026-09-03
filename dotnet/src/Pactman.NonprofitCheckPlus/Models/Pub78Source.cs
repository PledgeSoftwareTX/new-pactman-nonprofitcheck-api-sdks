using System.Collections.Generic;
using System.Text.Json;

namespace Pactman.NonprofitCheckPlus.Models
{
    /// <summary>IRS Publication 78 findings.</summary>
    public sealed class Pub78Source : SourceView
    {
        /// <summary>Initializes the view over the projected fields.</summary>
        /// <param name="fields">The fields copied from the organization.</param>
        public Pub78Source(IEnumerable<KeyValuePair<string, JsonElement>> fields)
            : base(fields)
        {
        }

        /// <summary>Whether the organization appears in Publication 78.</summary>
        public bool? Verified => GetBoolean("verified");

        /// <summary>The organization's name as Publication 78 records it.</summary>
        public string? OrganizationName => GetString("organization_name");

        /// <summary>The EIN as Publication 78 records it.</summary>
        public string? Ein => GetString("ein");

        /// <summary>The city as Publication 78 records it.</summary>
        public string? City => GetString("city");

        /// <summary>The state as Publication 78 records it.</summary>
        public string? State => GetString("state");

        /// <summary>The Publication 78 deductibility indicator.</summary>
        public string? Indicator => GetString("indicator");

        /// <summary>The note for organizations the IRS treats as churches.</summary>
        public string? ChurchMessage => GetString("church_message");

        /// <summary>
        /// The Publication 78 deductibility entries, as the API sent them.
        /// </summary>
        /// <remarks>
        /// Empty when the API sent none, so it is always safe to enumerate; ask
        /// <c>Has("organization_types")</c> when the difference matters.
        /// </remarks>
        public IReadOnlyList<OrganizationType> OrganizationTypes =>
            OrganizationType.ListFrom(GetElement("organization_types"));

        /// <summary>The date of the most recent Publication 78 extract behind this record.</summary>
        public string? MostRecent => GetString("most_recent");
    }
}
