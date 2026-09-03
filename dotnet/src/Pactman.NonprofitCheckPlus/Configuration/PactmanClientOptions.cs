using System;
using System.Collections.Generic;
using System.Net.Http;

namespace Pactman.NonprofitCheckPlus.Configuration
{
    /// <summary>
    /// Options for constructing a <see cref="PactmanClient"/>.
    /// </summary>
    /// <remarks>
    /// Everything unusable is rejected at construction, before any network call is
    /// attempted.
    /// </remarks>
    public sealed class PactmanClientOptions
    {
        /// <summary>
        /// Your Pactman API key.
        /// </summary>
        /// <remarks>
        /// Load it from the environment or a secret manager; never commit it, and never
        /// ship it to an end user. The client copies it at construction and does not keep
        /// a reference to these options.
        /// </remarks>
        public string? ApiKey { get; set; }

        /// <summary>Named Pactman environment. Defaults to production.</summary>
        public PactmanEnvironment? Environment { get; set; }

        /// <summary>
        /// Explicit base URL, for a mock server, a proxy, or a host Pactman has given you
        /// directly. Overrides <see cref="Environment"/> when set.
        /// </summary>
        public string? BaseUrl { get; set; }

        /// <summary>Timeout per attempt. Defaults to 30 seconds.</summary>
        public TimeSpan? Timeout { get; set; }

        /// <summary>Retry policy. Defaults to <see cref="RetryOptions.Default"/>.</summary>
        public RetryOptions? Retry { get; set; }

        /// <summary>
        /// Optional client-side ceiling on outbound requests per second.
        /// </summary>
        /// <remarks>
        /// Off by default; the server's limits are authoritative and may change.
        /// </remarks>
        public double? MaxRequestsPerSecond { get; set; }

        /// <summary>
        /// Extra headers sent with every request. Cannot override <c>Authorization</c>.
        /// </summary>
        public IDictionary<string, string> DefaultHeaders { get; } =
            new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);

        /// <summary>
        /// The <see cref="System.Net.Http.HttpClient"/> to send through.
        /// </summary>
        /// <remarks>
        /// <para>
        /// Leave this unset and the client creates and owns one. Supply your own — from
        /// <c>IHttpClientFactory</c>, with a custom handler, a proxy, or pinned
        /// certificates — and the client borrows it without disposing it unless
        /// <see cref="DisposeHttpClient"/> says otherwise.
        /// </para>
        /// <para>
        /// The SDK sets no <see cref="System.Net.Http.HttpClient.Timeout"/> of its own on a
        /// borrowed client: per-attempt deadlines are enforced with a cancellation token,
        /// so a shared client's own timeout stays whatever you set it to. Set it to
        /// <see cref="System.Threading.Timeout.InfiniteTimeSpan"/> if you want this SDK's
        /// timeout to be the only one in play.
        /// </para>
        /// </remarks>
        public HttpClient? HttpClient { get; set; }

        /// <summary>
        /// Dispose the supplied <see cref="HttpClient"/> when the Pactman client is disposed.
        /// </summary>
        /// <remarks>
        /// Ignored when the SDK created the client itself, which it always disposes.
        /// Leave this off for a client from <c>IHttpClientFactory</c> or any client you
        /// share.
        /// </remarks>
        public bool DisposeHttpClient { get; set; }
    }
}
