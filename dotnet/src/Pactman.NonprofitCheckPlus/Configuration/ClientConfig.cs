using System;
using System.Collections.Generic;

namespace Pactman.NonprofitCheckPlus.Configuration
{
    /// <summary>
    /// Fully-resolved client configuration.
    /// </summary>
    /// <remarks>
    /// The API key is deliberately not a property of this object, so no diagnostic that
    /// reaches for the configuration can print the credential.
    /// </remarks>
    public sealed class ClientConfig
    {
        /// <summary>Default timeout per attempt.</summary>
        public static readonly TimeSpan DefaultTimeout = TimeSpan.FromSeconds(30);

        /// <summary>Initializes the resolved configuration.</summary>
        /// <param name="baseUrl">The host every request is sent to.</param>
        /// <param name="environment">The named environment, or <see langword="null"/> when an explicit base URL was given.</param>
        /// <param name="timeout">Timeout per attempt.</param>
        /// <param name="retry">Retry policy.</param>
        /// <param name="maxRequestsPerSecond">Optional client-side outbound ceiling.</param>
        /// <param name="defaultHeaders">Extra headers sent with every request.</param>
        /// <param name="userAgent">The <c>User-Agent</c> this client reports.</param>
        public ClientConfig(
            string baseUrl,
            PactmanEnvironment? environment,
            TimeSpan timeout,
            RetryOptions retry,
            double? maxRequestsPerSecond,
            IReadOnlyDictionary<string, string> defaultHeaders,
            string userAgent)
        {
            BaseUrl = baseUrl;
            Environment = environment;
            Timeout = timeout;
            Retry = retry;
            MaxRequestsPerSecond = maxRequestsPerSecond;
            DefaultHeaders = defaultHeaders;
            UserAgent = userAgent;
        }

        /// <summary>The host every request is sent to.</summary>
        public string BaseUrl { get; }

        /// <summary>The named environment, or <see langword="null"/> when an explicit base URL was given.</summary>
        public PactmanEnvironment? Environment { get; }

        /// <summary>Timeout per attempt.</summary>
        public TimeSpan Timeout { get; }

        /// <summary>Retry policy.</summary>
        public RetryOptions Retry { get; }

        /// <summary>Optional client-side ceiling on outbound requests per second.</summary>
        public double? MaxRequestsPerSecond { get; }

        /// <summary>Extra headers sent with every request.</summary>
        public IReadOnlyDictionary<string, string> DefaultHeaders { get; }

        /// <summary>The <c>User-Agent</c> this client reports.</summary>
        public string UserAgent { get; }

        /// <summary>A serializable view of the configuration. Never contains the API key.</summary>
        /// <returns>The configuration's fields, keyed by name.</returns>
        public IReadOnlyDictionary<string, object?> ToDictionary() =>
            new Dictionary<string, object?>(StringComparer.Ordinal)
            {
                ["baseUrl"] = BaseUrl,
                ["environment"] = Environment?.Name(),
                ["timeout"] = Timeout.TotalSeconds,
                ["retry"] = Retry.ToDictionary(),
                ["maxRequestsPerSecond"] = MaxRequestsPerSecond,
                ["userAgent"] = UserAgent,
            };
    }
}
