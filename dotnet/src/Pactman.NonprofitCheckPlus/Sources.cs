using System;
using System.Collections.Generic;
using System.Text.Json;
using Pactman.NonprofitCheckPlus.Models;

namespace Pactman.NonprofitCheckPlus
{
    /// <summary>
    /// Grouped views over the source-specific findings on a <see cref="Nonprofit"/>.
    /// </summary>
    /// <remarks>
    /// <para>
    /// These are projections, not derivations: every key is copied 1:1 from a field the
    /// API returned. Nothing here computes an "approved", "eligible" or "safe" verdict,
    /// and nothing infers a value from another field.
    /// </para>
    /// <para>
    /// Each accessor returns <see langword="null"/> when the API returned no data at all
    /// for that source. That keeps "the source was not returned" distinguishable from an
    /// explicit negative such as <c>pub78_verified: false</c> or a null field.
    /// </para>
    /// <para>
    /// Every method is also an extension method, so
    /// <c>Sources.Pub78(organization)</c> and <c>organization.Pub78()</c> are the same call.
    /// </para>
    /// </remarks>
    public static class Sources
    {
        private static readonly KeyValuePair<string, string>[] Pub78Fields =
        {
            new KeyValuePair<string, string>("verified", "pub78_verified"),
            new KeyValuePair<string, string>("organization_name", "pub78_organization_name"),
            new KeyValuePair<string, string>("ein", "pub78_ein"),
            new KeyValuePair<string, string>("city", "pub78_city"),
            new KeyValuePair<string, string>("state", "pub78_state"),
            new KeyValuePair<string, string>("indicator", "pub78_indicator"),
            new KeyValuePair<string, string>("church_message", "pub78_church_message"),
            new KeyValuePair<string, string>("organization_types", "organization_types"),
            new KeyValuePair<string, string>("most_recent", "most_recent_pub78"),
        };

        private static readonly KeyValuePair<string, string>[] BmfFields =
        {
            new KeyValuePair<string, string>("status", "bmf_status"),
            new KeyValuePair<string, string>("organization_name", "bmf_organization_name"),
            new KeyValuePair<string, string>("ein", "bmf_ein"),
            new KeyValuePair<string, string>("church_message", "bmf_church_message"),
            new KeyValuePair<string, string>("subsection", "bmf_subsection"),
            new KeyValuePair<string, string>("subsection_description", "subsection_description"),
            new KeyValuePair<string, string>("foundation_code", "foundation_code"),
            new KeyValuePair<string, string>("foundation_code_description", "foundation_code_description"),
            new KeyValuePair<string, string>("foundation_type_code", "foundation_type_code"),
            new KeyValuePair<string, string>("foundation_type_description", "foundation_type_description"),
            new KeyValuePair<string, string>("foundation_509a_status", "foundation_509a_status"),
            new KeyValuePair<string, string>("ruling_month", "ruling_month"),
            new KeyValuePair<string, string>("ruling_year", "ruling_year"),
            new KeyValuePair<string, string>("group_exemption", "group_exemption"),
            new KeyValuePair<string, string>("exempt_status_code", "exempt_status_code"),
            new KeyValuePair<string, string>("filing_req_code", "filing_req_code"),
            new KeyValuePair<string, string>("most_recent", "most_recent_bmf"),
        };

        private static readonly KeyValuePair<string, string>[] AroeFields =
        {
            new KeyValuePair<string, string>("revocation_code", "revocation_code"),
            new KeyValuePair<string, string>("revocation_date", "revocation_date"),
            new KeyValuePair<string, string>("reinstatement_date", "reinstatement_date"),
        };

        private static readonly KeyValuePair<string, string>[] OfacFields =
        {
            new KeyValuePair<string, string>("status", "ofac_status"),
        };

        /// <summary>Publication 78 findings, or <see langword="null"/> if the API returned none.</summary>
        /// <param name="nonprofit">The organization to project.</param>
        /// <returns>The grouped findings, or <see langword="null"/>.</returns>
        public static Pub78Source? Pub78(this Nonprofit nonprofit)
        {
            var fields = Project(nonprofit, Pub78Fields);

            return fields is null ? null : new Pub78Source(fields);
        }

        /// <summary>Business Master File findings, or <see langword="null"/> if the API returned none.</summary>
        /// <param name="nonprofit">The organization to project.</param>
        /// <returns>The grouped findings, or <see langword="null"/>.</returns>
        public static BmfSource? Bmf(this Nonprofit nonprofit)
        {
            var fields = Project(nonprofit, BmfFields);

            return fields is null ? null : new BmfSource(fields);
        }

        /// <summary>
        /// Automatic Revocation of Exemption findings, or <see langword="null"/> if the API
        /// returned none.
        /// </summary>
        /// <param name="nonprofit">The organization to project.</param>
        /// <returns>The grouped findings, or <see langword="null"/>.</returns>
        public static AroeSource? Aroe(this Nonprofit nonprofit)
        {
            var fields = Project(nonprofit, AroeFields);

            return fields is null ? null : new AroeSource(fields);
        }

        /// <summary>OFAC findings, or <see langword="null"/> if the API returned none.</summary>
        /// <param name="nonprofit">The organization to project.</param>
        /// <returns>The grouped findings, or <see langword="null"/>.</returns>
        public static OfacSource? Ofac(this Nonprofit nonprofit)
        {
            var fields = Project(nonprofit, OfacFields);

            return fields is null ? null : new OfacSource(fields);
        }

        /// <summary>
        /// Copies the mapped fields into a new list, preserving null and false.
        /// </summary>
        /// <remarks>
        /// Returns <see langword="null"/> only when every mapped field is absent from the
        /// response, which is how "this source was not returned" is represented.
        /// </remarks>
        private static IReadOnlyList<KeyValuePair<string, JsonElement>>? Project(
            Nonprofit nonprofit,
            KeyValuePair<string, string>[] mapping)
        {
            if (nonprofit is null)
            {
                throw new ArgumentNullException(nameof(nonprofit));
            }

            var projected = new List<KeyValuePair<string, JsonElement>>(mapping.Length);

            foreach (var pair in mapping)
            {
                var element = nonprofit.GetElement(pair.Value);

                if (element.HasValue)
                {
                    projected.Add(new KeyValuePair<string, JsonElement>(pair.Key, element.Value));
                }
            }

            return projected.Count == 0 ? null : projected;
        }
    }
}
