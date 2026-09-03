using System;
using System.Collections.Generic;

namespace Pactman.NonprofitCheckPlus.Configuration
{
    /// <summary>Per-request overrides of the client's configuration.</summary>
    public class RequestOptions
    {
        /// <summary>
        /// Overrides the client's timeout for this request.
        /// </summary>
        /// <remarks>
        /// This is the deadline for one attempt, not for the call as a whole: a request
        /// that retries twice can take up to three times this. Bound the whole call with a
        /// <see cref="System.Threading.CancellationToken"/> instead.
        /// </remarks>
        public TimeSpan? Timeout { get; set; }

        /// <summary>
        /// Overrides the client's retry policy for this request.
        /// </summary>
        /// <remarks>
        /// A policy here replaces the client's outright. To adjust one setting, start from
        /// the policy in force: <c>client.Retry with { MaxRetries = 5 }</c>. Pass
        /// <see cref="RetryOptions.None"/> to disable retrying for this request.
        /// </remarks>
        public RetryOptions? Retry { get; set; }

        /// <summary>
        /// Extra headers for this request. Cannot override <c>Authorization</c>.
        /// </summary>
        public IDictionary<string, string> Headers { get; } =
            new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
    }
}
