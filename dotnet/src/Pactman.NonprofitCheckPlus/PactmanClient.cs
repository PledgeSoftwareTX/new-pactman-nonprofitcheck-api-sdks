using System;
using System.Collections.Generic;
using System.Globalization;
using System.Net.Http;
using Pactman.NonprofitCheckPlus.Configuration;
using Pactman.NonprofitCheckPlus.Exceptions;
using Pactman.NonprofitCheckPlus.Http;

using Pactman.NonprofitCheckPlus.Internal;

namespace Pactman.NonprofitCheckPlus
{
    /// <summary>
    /// The Pactman Nonprofit Check Plus client.
    /// </summary>
    /// <remarks>
    /// <para>
    /// Server-side use only. The API key is a private credential; do not construct this
    /// client anywhere its configuration is shipped to an end user.
    /// </para>
    /// <code>
    /// using var client = new PactmanClient(Environment.GetEnvironmentVariable("PACTMAN_API_KEY"));
    /// var result = await client.Nonprofits.CheckAsync("41-1787097");
    /// </code>
    /// <para>
    /// Build one client per process and share it — it is safe to use concurrently. Each
    /// instance carries its own connection pool and throttle state, so constructing one
    /// per request throws both away and, on a self-owned client, leaks sockets through
    /// <c>TIME_WAIT</c>. In an ASP.NET Core app, register it as a singleton and hand it an
    /// <c>IHttpClientFactory</c> client through <see cref="PactmanClientOptions.HttpClient"/>.
    /// </para>
    /// </remarks>
    public sealed class PactmanClient : IDisposable
    {
        private readonly ClientConfig _config;
        private readonly HttpClient _httpClient;
        private readonly bool _disposeHttpClient;

        private bool _disposed;

        /// <summary>Constructs a client for the production API with default options.</summary>
        /// <param name="apiKey">
        /// Your Pactman API key. Load it from the environment or a secret manager; never
        /// commit it, and never ship it to an end user.
        /// </param>
        /// <exception cref="PactmanConfigurationException">The key is missing or blank.</exception>
        public PactmanClient(string? apiKey)
            : this(new PactmanClientOptions { ApiKey = apiKey })
        {
        }

        /// <summary>Constructs a client from a full set of options.</summary>
        /// <param name="options">The options to resolve.</param>
        /// <exception cref="ArgumentNullException"><paramref name="options"/> is <see langword="null"/>.</exception>
        /// <exception cref="PactmanConfigurationException">
        /// A missing or blank API key, an unknown environment, a malformed base URL, or a
        /// nonsensical numeric option.
        /// </exception>
        public PactmanClient(PactmanClientOptions options)
            : this(options, null)
        {
        }

        internal PactmanClient(PactmanClientOptions options, TransportHooks? hooks)
        {
            if (options is null)
            {
                throw new ArgumentNullException(nameof(options));
            }

            var key = ConfigResolver.ApiKey(options.ApiKey);
            _config = ConfigResolver.Resolve(options);

            if (options.HttpClient is null)
            {
                // Deadlines are enforced per attempt with a cancellation token, so the
                // client's own timeout is stood down rather than racing ours.
                _httpClient = new HttpClient { Timeout = System.Threading.Timeout.InfiniteTimeSpan };
                _disposeHttpClient = true;
            }
            else
            {
                _httpClient = options.HttpClient;
                _disposeHttpClient = options.DisposeHttpClient;
            }

            // The key lives only inside this delegate. It is not a field of the client,
            // the configuration or the transport, so it appears in no property, no
            // ToString(), no ToDictionary() and nothing that serializes those.
            string Credential() => "Bearer " + key;

            Nonprofits = new NonprofitsResource(new Transport(Credential, _config, _httpClient, hooks));
        }

        /// <summary>Nonprofit lookups.</summary>
        public NonprofitsResource Nonprofits { get; }

        /// <summary>The resolved base URL every request is sent to.</summary>
        public string BaseUrl => _config.BaseUrl;

        /// <summary>
        /// The named environment in use, or <see langword="null"/> when an explicit base URL
        /// was given.
        /// </summary>
        public PactmanEnvironment? Environment => _config.Environment;

        /// <summary>The resolved timeout per attempt.</summary>
        public TimeSpan Timeout => _config.Timeout;

        /// <summary>The resolved retry policy.</summary>
        public RetryOptions Retry => _config.Retry;

        /// <summary>
        /// A redacted view of the configuration.
        /// </summary>
        /// <remarks>
        /// The API key is not a property of this object and never appears here, in
        /// <see cref="ToString"/>, or in anything that serializes either.
        /// </remarks>
        /// <returns>The configuration's fields, with the key redacted.</returns>
        public IReadOnlyDictionary<string, object?> ToDictionary()
        {
            var fields = new FieldMap(_config.ToDictionary())
            {
                ["apiKey"] = "[redacted]",
            };

            return fields;
        }

        /// <inheritdoc />
        public override string ToString() =>
            string.Format(CultureInfo.InvariantCulture, "PactmanClient({0})", _config.BaseUrl);

        /// <summary>
        /// Releases the HTTP client this instance owns.
        /// </summary>
        /// <remarks>
        /// A client supplied through <see cref="PactmanClientOptions.HttpClient"/> is left
        /// alone unless <see cref="PactmanClientOptions.DisposeHttpClient"/> asked otherwise,
        /// so disposing this does not tear down a pool you share.
        /// </remarks>
        public void Dispose()
        {
            if (_disposed)
            {
                return;
            }

            _disposed = true;

            if (_disposeHttpClient)
            {
                _httpClient.Dispose();
            }
        }
    }
}
