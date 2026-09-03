using System;
using System.Collections.Generic;
using System.Linq;

namespace Pactman.NonprofitCheckPlus.Models
{
    /// <summary>
    /// Fields shared by every result this SDK returns.
    /// </summary>
    /// <remarks>
    /// Results are shapes this SDK defines, so they are ordinary typed objects — unlike
    /// <see cref="Nonprofit"/>, whose shape the wire dictates.
    /// </remarks>
    public abstract class PactmanResult
    {
        /// <summary>Initializes the fields every result carries.</summary>
        /// <param name="checkCount">Checks consumed so far in the current billing cycle.</param>
        /// <param name="timeTakenMs">Server-side processing time in milliseconds, when reported.</param>
        /// <param name="errors">Item-level failures reported alongside the response.</param>
        /// <param name="requestId">Correlation identifier from the response headers, when present.</param>
        /// <param name="status">HTTP status of the response.</param>
        /// <param name="raw">The unmodified parsed response body.</param>
        protected PactmanResult(
            int? checkCount,
            double? timeTakenMs,
            IReadOnlyList<ApiErrorDetail> errors,
            string? requestId,
            int status,
            ResponseBody raw)
        {
            CheckCount = checkCount;
            TimeTakenMs = timeTakenMs;
            Errors = errors ?? Array.Empty<ApiErrorDetail>();
            RequestId = requestId;
            Status = status;
            Raw = raw ?? ResponseBody.Empty;
        }

        /// <summary>
        /// <c>nonprofit_check_count</c> from the envelope: checks consumed so far in the
        /// current billing cycle, including this request, resetting each cycle.
        /// </summary>
        /// <remarks>
        /// Not the size of this request — take the delta between two responses if you
        /// need that.
        /// </remarks>
        public int? CheckCount { get; }

        /// <summary>Server-side processing time in milliseconds, when reported.</summary>
        public double? TimeTakenMs { get; }

        /// <summary>
        /// Item-level failures reported alongside a successful response. Empty when the
        /// API reported none.
        /// </summary>
        public IReadOnlyList<ApiErrorDetail> Errors { get; }

        /// <summary>
        /// Correlation identifier from the response headers, when the server sent one.
        /// </summary>
        public string? RequestId { get; }

        /// <summary>HTTP status of the response.</summary>
        public int Status { get; }

        /// <summary>
        /// The unmodified parsed response body, including any field not typed above.
        /// </summary>
        /// <remarks>
        /// Normally the parsed envelope; a server that answers 200 with a non-JSON body
        /// leaves the raw text here rather than discarding the evidence.
        /// </remarks>
        public ResponseBody Raw { get; }

        /// <summary>A serializable view of the result, suitable for structured logging.</summary>
        /// <returns>The result's fields, keyed by name.</returns>
        public virtual IReadOnlyDictionary<string, object?> ToDictionary() =>
            new Dictionary<string, object?>(StringComparer.Ordinal)
            {
                ["checkCount"] = CheckCount,
                ["timeTakenMs"] = TimeTakenMs,
                ["errors"] = Errors.Select(detail => detail.ToDictionary()).ToList(),
                ["requestId"] = RequestId,
                ["status"] = Status,
            };
    }
}
