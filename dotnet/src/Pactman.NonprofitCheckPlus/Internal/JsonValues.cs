using System;
using System.Collections.Generic;
using System.Globalization;
using System.Text.Json;

namespace Pactman.NonprofitCheckPlus.Internal
{
    /// <summary>
    /// Conversions between <see cref="JsonElement"/> and plain CLR values.
    /// </summary>
    /// <remarks>
    /// Internal. Used to render wire data for logging and equality without forcing
    /// callers to reason about <see cref="JsonValueKind"/>.
    /// </remarks>
    internal static class JsonValues
    {
        /// <summary>
        /// Parses a JSON document into an element that owns its own memory.
        /// </summary>
        /// <remarks>
        /// Deserializing rather than <see cref="JsonDocument.Parse(string, JsonDocumentOptions)"/>
        /// matters: the returned element stays valid for the life of the object holding
        /// it, with no document to dispose and no use-after-dispose to get wrong.
        /// </remarks>
        internal static JsonElement Parse(string json) => JsonSerializer.Deserialize<JsonElement>(json);

        /// <summary>The object's properties in document order, or an empty sequence for anything else.</summary>
        internal static IEnumerable<KeyValuePair<string, JsonElement>> Properties(JsonElement element)
        {
            if (element.ValueKind != JsonValueKind.Object)
            {
                yield break;
            }

            foreach (var property in element.EnumerateObject())
            {
                yield return new KeyValuePair<string, JsonElement>(property.Name, property.Value);
            }
        }

        /// <summary>
        /// The element as a plain CLR value: <see langword="string"/>, <see langword="bool"/>,
        /// <see langword="double"/> or <see langword="long"/>, a list, a dictionary, or
        /// <see langword="null"/>.
        /// </summary>
        internal static object? ToClr(JsonElement element)
        {
            switch (element.ValueKind)
            {
                case JsonValueKind.String:
                    return element.GetString();

                case JsonValueKind.True:
                    return true;

                case JsonValueKind.False:
                    return false;

                case JsonValueKind.Number:
                    return element.TryGetInt64(out var integer) ? integer : element.GetDouble();

                case JsonValueKind.Array:
                    var items = new List<object?>();
                    foreach (var item in element.EnumerateArray())
                    {
                        items.Add(ToClr(item));
                    }

                    return items;

                case JsonValueKind.Object:
                    var fields = new Dictionary<string, object?>(StringComparer.Ordinal);
                    foreach (var property in element.EnumerateObject())
                    {
                        fields[property.Name] = ToClr(property.Value);
                    }

                    return fields;

                case JsonValueKind.Undefined:
                case JsonValueKind.Null:
                default:
                    return null;
            }
        }

        /// <summary>
        /// The element as a string, or <see langword="null"/> when it is absent or JSON null.
        /// </summary>
        /// <remarks>
        /// A number or boolean is rendered invariantly rather than refused: this API has
        /// changed a field's JSON type between releases, and a caller reading
        /// <c>ruling_year</c> should not start receiving <see langword="null"/> the day it
        /// ships as a number.
        /// </remarks>
        internal static string? AsString(JsonElement element) => element.ValueKind switch
        {
            JsonValueKind.String => element.GetString(),
            JsonValueKind.Number => element.TryGetInt64(out var integer)
                ? integer.ToString(CultureInfo.InvariantCulture)
                : element.GetDouble().ToString(CultureInfo.InvariantCulture),
            JsonValueKind.True => "true",
            JsonValueKind.False => "false",
            _ => null,
        };

        /// <summary>The element as a boolean, or <see langword="null"/> when it is not one.</summary>
        internal static bool? AsBoolean(JsonElement element) => element.ValueKind switch
        {
            JsonValueKind.True => true,
            JsonValueKind.False => false,
            _ => null,
        };

        /// <summary>The element as a double, or <see langword="null"/> when it is not a number.</summary>
        internal static double? AsDouble(JsonElement element) =>
            element.ValueKind == JsonValueKind.Number && element.TryGetDouble(out var value) ? value : (double?)null;

        /// <summary>The element as a 32-bit integer, or <see langword="null"/> when it is not one.</summary>
        internal static int? AsInt32(JsonElement element)
        {
            if (element.ValueKind != JsonValueKind.Number)
            {
                return null;
            }

            if (element.TryGetInt32(out var integer))
            {
                return integer;
            }

            // A count the server sent as 12.0 is still a count.
            return element.TryGetDouble(out var number) && number >= int.MinValue && number <= int.MaxValue
                ? (int)number
                : (int?)null;
        }
    }
}
