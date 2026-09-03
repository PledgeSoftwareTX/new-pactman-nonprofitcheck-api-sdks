using System;
using System.Collections.Generic;
using System.Linq;

using Pactman.NonprofitCheckPlus.Internal;

namespace Pactman.NonprofitCheckPlus.Exceptions
{
    /// <summary>
    /// Input failed local validation. No HTTP request was sent.
    /// </summary>
    /// <remarks>
    /// Distinguishable from an API-side 400 by <see cref="PactmanException.Origin"/>
    /// being <see cref="ErrorOrigin.Local"/>.
    /// </remarks>
    public sealed class PactmanValidationException : PactmanException
    {
        /// <summary>Initializes the exception.</summary>
        /// <param name="message">A summary naming how many items failed and where.</param>
        /// <param name="issues">The individual failures, in input order.</param>
        public PactmanValidationException(string message, IReadOnlyList<ValidationIssue>? issues = null)
            : base(message, ErrorCategory.Validation, ErrorOrigin.Local)
        {
            Issues = issues ?? Array.Empty<ValidationIssue>();
        }

        /// <summary>The individual failures, in input order.</summary>
        public IReadOnlyList<ValidationIssue> Issues { get; }

        /// <inheritdoc />
        public override IReadOnlyDictionary<string, object?> ToDictionary()
        {
            var fields = new FieldMap(base.ToDictionary())
            {
                ["issues"] = Issues.Select(issue => issue.ToDictionary()).ToList(),
            };

            return fields;
        }
    }
}
