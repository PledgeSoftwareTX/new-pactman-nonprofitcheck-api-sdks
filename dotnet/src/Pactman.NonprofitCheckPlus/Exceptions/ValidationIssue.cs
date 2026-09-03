using System;
using System.Collections.Generic;

namespace Pactman.NonprofitCheckPlus.Exceptions
{
    /// <summary>One item that failed local validation.</summary>
    public sealed class ValidationIssue
    {
        /// <summary>Initializes the issue.</summary>
        /// <param name="message">Human-readable reason the value was rejected.</param>
        /// <param name="index">Position in the input collection, for bulk calls.</param>
        /// <param name="value">The offending value, as supplied by the caller.</param>
        public ValidationIssue(string message, int? index = null, object? value = null)
        {
            Message = message;
            Index = index;
            Value = value;
        }

        /// <summary>Human-readable reason the value was rejected.</summary>
        public string Message { get; }

        /// <summary>Position in the input collection, for bulk calls.</summary>
        public int? Index { get; }

        /// <summary>The offending value, as supplied by the caller.</summary>
        public object? Value { get; }

        /// <summary>A serializable view of the issue.</summary>
        /// <returns>The issue's fields, keyed by name.</returns>
        public IReadOnlyDictionary<string, object?> ToDictionary() =>
            new Dictionary<string, object?>(StringComparer.Ordinal)
            {
                ["message"] = Message,
                ["index"] = Index,
                ["value"] = Value,
            };
    }
}
