using System;
using System.Collections.Generic;

namespace Pactman.NonprofitCheckPlus.Internal
{
    /// <summary>
    /// A field map for <c>ToDictionary()</c>, seeded from a base class's fields.
    /// </summary>
    /// <remarks>
    /// Internal. Exists because <see cref="Dictionary{TKey, TValue}"/> on netstandard2.0
    /// has no constructor taking an <see cref="IReadOnlyDictionary{TKey, TValue}"/>, so
    /// "the base class's fields, plus mine" needs one spelling that compiles on every
    /// target — and one that an object initializer can still extend.
    /// </remarks>
    internal sealed class FieldMap : Dictionary<string, object?>
    {
        /// <summary>Starts an empty map with ordinal key comparison.</summary>
        internal FieldMap()
            : base(StringComparer.Ordinal)
        {
        }

        /// <summary>Starts a map holding a copy of <paramref name="fields"/>.</summary>
        internal FieldMap(IReadOnlyDictionary<string, object?> fields)
            : base(fields.Count, StringComparer.Ordinal)
        {
            foreach (var field in fields)
            {
                this[field.Key] = field.Value;
            }
        }
    }
}
