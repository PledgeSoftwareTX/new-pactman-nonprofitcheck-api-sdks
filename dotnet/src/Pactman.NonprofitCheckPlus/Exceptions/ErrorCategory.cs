using System;

namespace Pactman.NonprofitCheckPlus.Exceptions
{
    /// <summary>
    /// Stable, machine-comparable error categories.
    /// </summary>
    /// <remarks>
    /// The wire values returned by <see cref="ErrorCategories.ToWireValue"/> match the
    /// other Pactman SDKs exactly, so a category logged by the .NET client is the
    /// same string a Node, Python or PHP service would log for the same failure.
    /// </remarks>
    public enum ErrorCategory
    {
        /// <summary>The client was constructed with unusable options.</summary>
        Configuration = 0,

        /// <summary>Input failed the SDK's local validation; no request was sent.</summary>
        Validation = 1,

        /// <summary>HTTP 401. The API key is missing, malformed, revoked or unrecognized.</summary>
        Authentication = 2,

        /// <summary>HTTP 403. The key is valid but lacks access to the resource.</summary>
        Authorization = 3,

        /// <summary>HTTP 400. The API rejected the request.</summary>
        BadRequest = 4,

        /// <summary>HTTP 404. No matching record.</summary>
        NotFound = 5,

        /// <summary>HTTP 429. Rate limit exceeded.</summary>
        RateLimit = 6,

        /// <summary>HTTP 5xx.</summary>
        Server = 7,

        /// <summary>The request exceeded the configured timeout.</summary>
        Timeout = 8,

        /// <summary>The request never produced an HTTP response.</summary>
        Network = 9,

        /// <summary>An API error that does not fall into a more specific category.</summary>
        Api = 10,
    }

    /// <summary>Wire spellings for <see cref="ErrorCategory"/>.</summary>
    public static class ErrorCategories
    {
        /// <summary>
        /// The category's wire value — the string the other Pactman SDKs log for the
        /// same failure.
        /// </summary>
        /// <param name="category">The category to spell.</param>
        /// <returns>The canonical snake-case name.</returns>
        /// <exception cref="ArgumentOutOfRangeException">The value is not a declared category.</exception>
        public static string ToWireValue(this ErrorCategory category) => category switch
        {
            ErrorCategory.Configuration => "configuration",
            ErrorCategory.Validation => "validation",
            ErrorCategory.Authentication => "authentication",
            ErrorCategory.Authorization => "authorization",
            ErrorCategory.BadRequest => "bad_request",
            ErrorCategory.NotFound => "not_found",
            ErrorCategory.RateLimit => "rate_limit",
            ErrorCategory.Server => "server",
            ErrorCategory.Timeout => "timeout",
            ErrorCategory.Network => "network",
            ErrorCategory.Api => "api",
            _ => throw new ArgumentOutOfRangeException(nameof(category), category, "Unknown error category."),
        };
    }
}
