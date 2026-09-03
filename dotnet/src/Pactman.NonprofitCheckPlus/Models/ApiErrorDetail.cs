using System;
using System.Collections.Generic;
using System.Text.Json;
using Pactman.NonprofitCheckPlus.Internal;

namespace Pactman.NonprofitCheckPlus.Models
{
    /// <summary>
    /// One entry from the response envelope's <c>errors</c> array.
    /// </summary>
    /// <remarks>
    /// Item-level failures appear on successful responses too — a bulk request where
    /// some EINs were not found returns HTTP 200 with entries here.
    /// </remarks>
    public sealed class ApiErrorDetail
    {
        private readonly IReadOnlyDictionary<string, object?> _raw;

        /// <summary>Initializes the entry.</summary>
        /// <param name="resource">The API resource the error came from.</param>
        /// <param name="reason">Human-readable explanation.</param>
        /// <param name="code">Status code for this specific failure, which may differ from the HTTP status.</param>
        /// <param name="eins">EINs this error applies to, for bulk requests.</param>
        /// <param name="raw">The entry exactly as the API sent it.</param>
        public ApiErrorDetail(
            string? resource = null,
            string? reason = null,
            int? code = null,
            IReadOnlyList<string>? eins = null,
            IReadOnlyDictionary<string, object?>? raw = null)
        {
            Resource = resource;
            Reason = reason;
            Code = code;
            Eins = eins ?? Array.Empty<string>();
            _raw = raw ?? new Dictionary<string, object?>(StringComparer.Ordinal);
        }

        /// <summary>The API resource the error came from.</summary>
        public string? Resource { get; }

        /// <summary>Human-readable explanation.</summary>
        public string? Reason { get; }

        /// <summary>
        /// Status code for this specific failure, which may differ from the HTTP status.
        /// </summary>
        public int? Code { get; }

        /// <summary>
        /// EINs this error applies to, for bulk requests.
        /// </summary>
        /// <remarks>
        /// The API sends either a list or a comma-separated string; both arrive here as a list.
        /// </remarks>
        public IReadOnlyList<string> Eins { get; }

        /// <summary>Builds an entry from the JSON the API sent.</summary>
        /// <param name="element">The entry as the API sent it.</param>
        /// <returns>The parsed entry, with the original preserved for logging.</returns>
        public static ApiErrorDetail FromJson(JsonElement element)
        {
            if (element.ValueKind != JsonValueKind.Object)
            {
                return new ApiErrorDetail();
            }

            var raw = new Dictionary<string, object?>(StringComparer.Ordinal);

            foreach (var property in element.EnumerateObject())
            {
                raw[property.Name] = JsonValues.ToClr(property.Value);
            }

            return new ApiErrorDetail(
                resource: Read(element, "resource", JsonValues.AsString),
                reason: Read(element, "reason", JsonValues.AsString),
                code: Read(element, "code", JsonValues.AsInt32),
                eins: NormalizeEins(element),
                raw: raw);
        }

        /// <summary>Builds an entry from a bare reason string.</summary>
        /// <param name="reason">The explanation the API sent in place of an object.</param>
        /// <returns>An entry carrying only the reason.</returns>
        public static ApiErrorDetail FromReason(string reason) =>
            new ApiErrorDetail(
                reason: reason,
                raw: new Dictionary<string, object?>(StringComparer.Ordinal) { ["reason"] = reason });

        /// <summary>
        /// The entry exactly as the API sent it. This is the form to log.
        /// </summary>
        /// <returns>Every field the API sent, including any not named above.</returns>
        public IReadOnlyDictionary<string, object?> ToDictionary() => _raw;

        /// <inheritdoc />
        public override string ToString() => Reason ?? Resource ?? "Pactman API error";

        private static T? Read<T>(JsonElement element, string name, Func<JsonElement, T?> read) =>
            element.TryGetProperty(name, out var value) ? read(value) : default;

        private static IReadOnlyList<string> NormalizeEins(JsonElement element)
        {
            if (!element.TryGetProperty("eins", out var eins))
            {
                return Array.Empty<string>();
            }

            var values = new List<string>();

            if (eins.ValueKind == JsonValueKind.Array)
            {
                foreach (var entry in eins.EnumerateArray())
                {
                    if (entry.ValueKind == JsonValueKind.String)
                    {
                        var value = entry.GetString();

                        if (!string.IsNullOrEmpty(value))
                        {
                            values.Add(value!);
                        }
                    }
                }

                return values;
            }

            if (eins.ValueKind == JsonValueKind.String)
            {
                foreach (var part in (eins.GetString() ?? string.Empty).Split(','))
                {
                    var trimmed = part.Trim();

                    if (trimmed.Length > 0)
                    {
                        values.Add(trimmed);
                    }
                }
            }

            return values;
        }
    }
}
