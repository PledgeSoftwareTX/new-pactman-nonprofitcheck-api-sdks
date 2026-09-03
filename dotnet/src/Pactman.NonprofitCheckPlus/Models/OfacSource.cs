using System.Collections.Generic;
using System.Text.Json;

namespace Pactman.NonprofitCheckPlus.Models
{
    /// <summary>OFAC Specially Designated Nationals findings.</summary>
    public sealed class OfacSource : SourceView
    {
        /// <summary>Initializes the view over the projected fields.</summary>
        /// <param name="fields">The fields copied from the organization.</param>
        public OfacSource(IEnumerable<KeyValuePair<string, JsonElement>> fields)
            : base(fields)
        {
        }

        /// <summary>
        /// The finding as the API phrases it.
        /// </summary>
        /// <remarks>
        /// This is prose, not a flag. The API does not currently return a boolean match
        /// indicator, and this SDK does not invent one by matching on the wording.
        /// </remarks>
        public string? Status => GetString("status");
    }
}
