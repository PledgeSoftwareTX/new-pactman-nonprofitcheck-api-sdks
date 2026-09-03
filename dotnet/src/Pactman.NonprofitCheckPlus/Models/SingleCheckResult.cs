using System;
using System.Collections.Generic;

using Pactman.NonprofitCheckPlus.Internal;

namespace Pactman.NonprofitCheckPlus.Models
{
    /// <summary>
    /// The result of <see cref="NonprofitsResource.CheckAsync"/>.
    /// </summary>
    public sealed class SingleCheckResult : PactmanResult
    {
        /// <summary>Initializes the result.</summary>
        /// <param name="checkCount">Checks consumed so far in the current billing cycle.</param>
        /// <param name="timeTakenMs">Server-side processing time in milliseconds, when reported.</param>
        /// <param name="errors">Item-level failures reported alongside the response.</param>
        /// <param name="requestId">Correlation identifier from the response headers, when present.</param>
        /// <param name="status">HTTP status of the response.</param>
        /// <param name="raw">The unmodified parsed response body.</param>
        /// <param name="nonprofit">The organization, or <see langword="null"/> when the API returned no record.</param>
        public SingleCheckResult(
            int? checkCount,
            double? timeTakenMs,
            IReadOnlyList<ApiErrorDetail> errors,
            string? requestId,
            int status,
            ResponseBody raw,
            Nonprofit? nonprofit)
            : base(checkCount, timeTakenMs, errors, requestId, status, raw)
        {
            Nonprofit = nonprofit;
        }

        /// <summary>The organization, or <see langword="null"/> when the API returned no record.</summary>
        public Nonprofit? Nonprofit { get; }

        /// <inheritdoc />
        public override IReadOnlyDictionary<string, object?> ToDictionary() =>
            new FieldMap(base.ToDictionary())
            {
                ["nonprofit"] = Nonprofit?.ToDictionary(),
            };
    }
}
