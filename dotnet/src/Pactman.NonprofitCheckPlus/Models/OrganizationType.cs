using System;
using System.Collections.Generic;
using System.Text.Json;

namespace Pactman.NonprofitCheckPlus.Models
{
    /// <summary>
    /// One Publication 78 deductibility entry from a nonprofit's <c>organization_types</c>.
    /// </summary>
    /// <remarks>
    /// Fields a newer API version adds stay readable through
    /// <see cref="DataObject.Get(string)"/>, exactly as on the organization itself.
    /// </remarks>
    public sealed class OrganizationType : DataObject
    {
        /// <summary>Initializes the entry from a decoded JSON object.</summary>
        /// <param name="element">The entry as the API sent it.</param>
        public OrganizationType(JsonElement element)
            : base(element)
        {
        }

        /// <summary>The Publication 78 organization type code.</summary>
        public string? Type => GetString("organization_type");

        /// <summary>The deductibility limitation the IRS records for this type.</summary>
        public string? DeductibilityLimitation => GetString("deductibility_limitation");

        /// <summary>The deductibility status, in the IRS's own words.</summary>
        public string? DeductibilityStatusDescription => GetString("deductibility_status_description");

        /// <summary>
        /// Reads a deductibility list, dropping entries the API could not resolve.
        /// </summary>
        /// <remarks>
        /// The API can send a null in the list, for a Publication 78 row it cannot
        /// resolve. Those are dropped rather than handed on, so every entry returned is a
        /// real object and the positions are renumbered from zero.
        /// </remarks>
        internal static IReadOnlyList<OrganizationType> ListFrom(JsonElement? element)
        {
            if (!element.HasValue || element.Value.ValueKind != JsonValueKind.Array)
            {
                return Array.Empty<OrganizationType>();
            }

            var entries = new List<OrganizationType>();

            foreach (var entry in element.Value.EnumerateArray())
            {
                if (entry.ValueKind == JsonValueKind.Object)
                {
                    entries.Add(new OrganizationType(entry));
                }
            }

            return entries;
        }
    }
}
