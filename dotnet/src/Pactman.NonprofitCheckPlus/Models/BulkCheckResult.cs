using System;
using System.Collections.Generic;
using System.Linq;

using Pactman.NonprofitCheckPlus.Internal;

namespace Pactman.NonprofitCheckPlus.Models
{
    /// <summary>
    /// The result of <see cref="NonprofitsResource.CheckBulkAsync"/>.
    /// </summary>
    public sealed class BulkCheckResult : PactmanResult
    {
        /// <summary>Initializes the result.</summary>
        /// <param name="checkCount">Checks consumed so far in the current billing cycle.</param>
        /// <param name="timeTakenMs">Server-side processing time in milliseconds, when reported.</param>
        /// <param name="errors">Item-level failures reported alongside the response.</param>
        /// <param name="requestId">Correlation identifier from the response headers, when present.</param>
        /// <param name="status">HTTP status of the response.</param>
        /// <param name="raw">The unmodified parsed response body.</param>
        /// <param name="organizations">Organizations the API matched, in the order it returned them.</param>
        /// <param name="notFoundEins">EINs the API reported no record for.</param>
        public BulkCheckResult(
            int? checkCount,
            double? timeTakenMs,
            IReadOnlyList<ApiErrorDetail> errors,
            string? requestId,
            int status,
            ResponseBody raw,
            IReadOnlyList<Nonprofit> organizations,
            IReadOnlyList<string> notFoundEins)
            : base(checkCount, timeTakenMs, errors, requestId, status, raw)
        {
            Organizations = organizations ?? Array.Empty<Nonprofit>();
            NotFoundEins = notFoundEins ?? Array.Empty<string>();
        }

        /// <summary>
        /// Organizations the API matched, in the order it returned them — which is not
        /// guaranteed to follow the order you supplied. Index by EIN with
        /// <see cref="ByEin"/>.
        /// </summary>
        public IReadOnlyList<Nonprofit> Organizations { get; }

        /// <summary>
        /// EINs the API reported no record for, collected from <see cref="PactmanResult.Errors"/>.
        /// </summary>
        /// <remarks>
        /// A bulk request where some EINs miss is a successful HTTP 200, not an error.
        /// </remarks>
        public IReadOnlyList<string> NotFoundEins { get; }

        /// <summary>
        /// The matched organizations keyed by the EIN the API echoed back.
        /// </summary>
        /// <remarks>
        /// <para>
        /// This is the pairing that always holds. The response is a set of matched
        /// records, not a row-for-row answer to your input list, so never pair
        /// <see cref="Organizations"/> positionally with the EINs you sent.
        /// </para>
        /// <para>
        /// Records the API returned without an <c>ein</c> are skipped, since there is no
        /// key to file them under; read <see cref="Organizations"/> directly if you need
        /// them. Keys are the normalized nine-digit form the API returns, so look up with
        /// <see cref="Ein.Normalize(string, int?)"/> rather than the hyphenated string you
        /// may have supplied.
        /// </para>
        /// </remarks>
        /// <returns>The organizations, keyed by EIN.</returns>
        public IReadOnlyDictionary<string, Nonprofit> ByEin()
        {
            var indexed = new Dictionary<string, Nonprofit>(Organizations.Count, StringComparer.Ordinal);

            foreach (var organization in Organizations)
            {
                var ein = organization.Ein;

                if (!string.IsNullOrEmpty(ein))
                {
                    indexed[ein!] = organization;
                }
            }

            return indexed;
        }

        /// <inheritdoc />
        public override IReadOnlyDictionary<string, object?> ToDictionary() =>
            new FieldMap(base.ToDictionary())
            {
                ["organizations"] = Organizations.Select(organization => organization.ToDictionary()).ToList(),
                ["notFoundEins"] = NotFoundEins.ToList(),
            };
    }
}
