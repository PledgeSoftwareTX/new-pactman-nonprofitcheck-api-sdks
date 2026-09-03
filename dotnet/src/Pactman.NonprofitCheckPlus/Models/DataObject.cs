using System;
using System.Collections;
using System.Collections.Generic;
using System.IO;
using System.Text;
using System.Text.Json;
using Pactman.NonprofitCheckPlus.Internal;

namespace Pactman.NonprofitCheckPlus.Models
{
    /// <summary>
    /// An immutable view over a decoded JSON object.
    /// </summary>
    /// <remarks>
    /// <para>
    /// Wire field names are preserved exactly, so what you read in the Pactman API
    /// reference is what <see cref="Has(string)"/> and <see cref="Get(string)"/> take —
    /// there is no rename table to keep in sync. Typed properties on the derived
    /// classes are conveniences over the same store, not a separate deserialization:
    /// a field the API adds in a future version stays readable through
    /// <see cref="Get(string)"/> without a deserialization failure or an SDK upgrade.
    /// </para>
    /// <para>
    /// <b><see cref="Has(string)"/> answers "did the API return this field?"</b> — it
    /// reports <see langword="true"/> for a field returned as JSON <c>null</c>. That
    /// distinction is load-bearing for this API: "no data for this source" and "this
    /// source says null" route differently, and collapsing them loses a finding. Use
    /// <see cref="Get(string)"/> and the typed accessors to read the value,
    /// <see cref="Has(string)"/> to ask whether the API sent the field at all.
    /// </para>
    /// </remarks>
    public abstract class DataObject : IEnumerable<KeyValuePair<string, JsonElement>>
    {
        private readonly KeyValuePair<string, JsonElement>[] _fields;
        private readonly Dictionary<string, int> _index;

        /// <summary>Initializes the view over a set of wire fields, in document order.</summary>
        /// <param name="fields">The fields exactly as they were decoded.</param>
        protected DataObject(IEnumerable<KeyValuePair<string, JsonElement>>? fields)
        {
            _fields = fields is null
                ? Array.Empty<KeyValuePair<string, JsonElement>>()
                : new List<KeyValuePair<string, JsonElement>>(fields).ToArray();

            _index = new Dictionary<string, int>(_fields.Length, StringComparer.Ordinal);

            for (var i = 0; i < _fields.Length; i++)
            {
                // A duplicate key is legal JSON; the last one wins, as every JSON
                // parser this SDK's callers use would also resolve it.
                _index[_fields[i].Key] = i;
            }
        }

        /// <summary>Initializes the view from a decoded JSON object.</summary>
        /// <param name="element">The JSON object. Any other value kind yields an empty view.</param>
        protected DataObject(JsonElement element)
            : this(JsonValues.Properties(element))
        {
        }

        /// <summary>How many fields the API returned.</summary>
        public int Count => _fields.Length;

        /// <summary>The field names the API returned, in the order it returned them.</summary>
        public IEnumerable<string> FieldNames
        {
            get
            {
                foreach (var field in _fields)
                {
                    yield return field.Key;
                }
            }
        }

        /// <summary>
        /// The field's raw JSON, or <see langword="null"/> when the API did not return it.
        /// </summary>
        /// <param name="field">The wire field name.</param>
        /// <returns>The raw element, or <see langword="null"/> when absent.</returns>
        public JsonElement? this[string field] => GetElement(field);

        /// <summary>
        /// True when the API returned this field, including when it returned it as JSON <c>null</c>.
        /// </summary>
        /// <param name="field">The wire field name.</param>
        /// <returns><see langword="true"/> when the field was present in the response.</returns>
        public bool Has(string field) => field != null && _index.ContainsKey(field);

        /// <summary>The field's raw JSON, or <see langword="null"/> when the API did not return it.</summary>
        /// <param name="field">The wire field name.</param>
        /// <returns>The raw element, or <see langword="null"/> when absent.</returns>
        public JsonElement? GetElement(string field)
        {
            if (field != null && _index.TryGetValue(field, out var position))
            {
                return _fields[position].Value;
            }

            return null;
        }

        /// <summary>
        /// The field as a plain CLR value, or <see langword="null"/> when it is absent or JSON null.
        /// </summary>
        /// <param name="field">The wire field name.</param>
        /// <returns>A string, boolean, number, list, dictionary, or <see langword="null"/>.</returns>
        public object? Get(string field)
        {
            var element = GetElement(field);

            return element.HasValue ? JsonValues.ToClr(element.Value) : null;
        }

        /// <summary>
        /// The field deserialized into <typeparamref name="T"/>, or <see langword="default"/>
        /// when it is absent or JSON null.
        /// </summary>
        /// <typeparam name="T">The shape to deserialize into.</typeparam>
        /// <param name="field">The wire field name.</param>
        /// <param name="options">Serializer options, when the default is not wanted.</param>
        /// <returns>The deserialized value, or <see langword="default"/>.</returns>
        /// <exception cref="JsonException">The field is not shaped like <typeparamref name="T"/>.</exception>
        public T? Get<T>(string field, JsonSerializerOptions? options = null)
        {
            var element = GetElement(field);

            if (!element.HasValue || element.Value.ValueKind == JsonValueKind.Null)
            {
                return default;
            }

            return element.Value.Deserialize<T>(options);
        }

        /// <summary>The field as a string, or <see langword="null"/> when it is absent or JSON null.</summary>
        /// <param name="field">The wire field name.</param>
        /// <returns>The string value, or <see langword="null"/>.</returns>
        public string? GetString(string field)
        {
            var element = GetElement(field);

            return element.HasValue ? JsonValues.AsString(element.Value) : null;
        }

        /// <summary>The field as a boolean, or <see langword="null"/> when it is absent or not a boolean.</summary>
        /// <param name="field">The wire field name.</param>
        /// <returns>The boolean value, or <see langword="null"/>.</returns>
        public bool? GetBoolean(string field)
        {
            var element = GetElement(field);

            return element.HasValue ? JsonValues.AsBoolean(element.Value) : null;
        }

        /// <summary>The field as a number, or <see langword="null"/> when it is absent or not a number.</summary>
        /// <param name="field">The wire field name.</param>
        /// <returns>The numeric value, or <see langword="null"/>.</returns>
        public double? GetDouble(string field)
        {
            var element = GetElement(field);

            return element.HasValue ? JsonValues.AsDouble(element.Value) : null;
        }

        /// <summary>The field as a 32-bit integer, or <see langword="null"/> when it is absent or not a number.</summary>
        /// <param name="field">The wire field name.</param>
        /// <returns>The integer value, or <see langword="null"/>.</returns>
        public int? GetInt32(string field)
        {
            var element = GetElement(field);

            return element.HasValue ? JsonValues.AsInt32(element.Value) : null;
        }

        /// <summary>The unmodified fields, exactly as they were decoded.</summary>
        /// <returns>The wire fields as plain CLR values, in the order the API returned them.</returns>
        public IReadOnlyDictionary<string, object?> ToDictionary()
        {
            var fields = new Dictionary<string, object?>(_fields.Length, StringComparer.Ordinal);

            foreach (var field in _fields)
            {
                fields[field.Key] = JsonValues.ToClr(field.Value);
            }

            return fields;
        }

        /// <summary>The fields re-serialized as a JSON object, in the order the API returned them.</summary>
        /// <returns>A JSON object literal.</returns>
        public string ToJson()
        {
            using var buffer = new MemoryStream();

            using (var writer = new Utf8JsonWriter(buffer))
            {
                writer.WriteStartObject();

                foreach (var field in _fields)
                {
                    writer.WritePropertyName(field.Key);
                    field.Value.WriteTo(writer);
                }

                writer.WriteEndObject();
            }

            return Encoding.UTF8.GetString(buffer.ToArray());
        }

        /// <inheritdoc />
        public IEnumerator<KeyValuePair<string, JsonElement>> GetEnumerator()
        {
            foreach (var field in _fields)
            {
                yield return field;
            }
        }

        /// <inheritdoc />
        public override string ToString() => ToJson();

        IEnumerator IEnumerable.GetEnumerator() => GetEnumerator();
    }
}
