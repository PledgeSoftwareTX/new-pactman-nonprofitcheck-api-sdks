using System.Collections.Generic;
using System.Text.Json;

namespace Pactman.NonprofitCheckPlus.Models
{
    /// <summary>
    /// A grouped view over one source's findings on a <see cref="Nonprofit"/>.
    /// </summary>
    /// <remarks>
    /// A projection, not a derivation: every key is copied 1:1 from a field the API
    /// returned. Nothing here computes an "approved", "eligible" or "safe" verdict, and
    /// nothing infers a value from another field.
    /// <para>
    /// Only the keys the API actually returned are present, so
    /// <see cref="DataObject.Has(string)"/> still answers "did the API send this?"
    /// exactly as it does on the organization itself.
    /// </para>
    /// </remarks>
    public abstract class SourceView : DataObject
    {
        /// <summary>Initializes the view over the projected fields.</summary>
        /// <param name="fields">The fields copied from the organization, in source order.</param>
        protected SourceView(IEnumerable<KeyValuePair<string, JsonElement>> fields)
            : base(fields)
        {
        }
    }
}
