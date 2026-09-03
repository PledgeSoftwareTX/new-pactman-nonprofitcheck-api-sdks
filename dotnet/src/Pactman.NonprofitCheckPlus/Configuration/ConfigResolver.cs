using System;
using System.Collections.Generic;
using System.Globalization;
using System.Runtime.InteropServices;
using System.Text;
using Pactman.NonprofitCheckPlus.Exceptions;

namespace Pactman.NonprofitCheckPlus.Configuration
{
    /// <summary>
    /// Validates and resolves constructor options.
    /// </summary>
    /// <remarks>
    /// Everything unusable is rejected here, at construction, before any network call is
    /// attempted.
    /// </remarks>
    public static class ConfigResolver
    {
        /// <summary>Validates and trims an API key.</summary>
        /// <param name="apiKey">The key as supplied.</param>
        /// <returns>The trimmed key.</returns>
        /// <exception cref="PactmanConfigurationException">The key is missing or blank.</exception>
        public static string ApiKey(string? apiKey)
        {
            if (apiKey is null)
            {
                throw new PactmanConfigurationException(
                    "A Pactman API key is required. Pass ApiKey, for example from "
                    + "Environment.GetEnvironmentVariable(\"PACTMAN_API_KEY\").");
            }

            var trimmed = apiKey.Trim();

            if (trimmed.Length == 0)
            {
                throw new PactmanConfigurationException(
                    "The Pactman API key is empty. Check that the environment variable holding it is set.");
            }

            return trimmed;
        }

        /// <summary>Resolves client options into a validated configuration.</summary>
        /// <param name="options">The options as supplied.</param>
        /// <returns>The fully-resolved configuration.</returns>
        /// <exception cref="PactmanConfigurationException">
        /// An unknown environment, a malformed base URL, or a nonsensical numeric option.
        /// </exception>
        public static ClientConfig Resolve(PactmanClientOptions options)
        {
            if (options is null)
            {
                throw new ArgumentNullException(nameof(options));
            }

            // Any supplied value goes through validation, blank included. A base URL of
            // "  " means a misconfigured environment variable, and quietly falling back
            // to production is the one outcome nobody wants from that.
            var hasExplicitBaseUrl = options.BaseUrl != null;
            var environment = options.Environment ?? PactmanEnvironments.Default;

            var headers = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);

            foreach (var header in options.DefaultHeaders)
            {
                headers[header.Key] = header.Value;
            }

            return new ClientConfig(
                baseUrl: hasExplicitBaseUrl ? ValidateBaseUrl(options.BaseUrl!) : environment.BaseUrl(),
                environment: hasExplicitBaseUrl ? (PactmanEnvironment?)null : environment,
                timeout: ResolveTimeout(options.Timeout),
                retry: options.Retry ?? RetryOptions.Default,
                maxRequestsPerSecond: ResolveRequestsPerSecond(options.MaxRequestsPerSecond),
                defaultHeaders: headers,
                userAgent: BuildUserAgent());
        }

        /// <summary>
        /// Builds the <c>User-Agent</c>: <c>Pactman.NonprofitCheckPlus/&lt;version&gt; (dotnet/&lt;runtime&gt;; &lt;os&gt;)</c>.
        /// </summary>
        /// <returns>A header-safe user agent string.</returns>
        public static string BuildUserAgent() => string.Format(
            CultureInfo.InvariantCulture,
            "{0}/{1} (dotnet/{2}; {3})",
            SdkVersion.PackageName,
            SdkVersion.Version,
            HeaderSafe(RuntimeInformation.FrameworkDescription),
            HeaderSafe(RuntimeInformation.OSDescription));

        /// <summary>Validates an environment name and resolves it.</summary>
        /// <param name="name">The environment name, such as <c>production</c>.</param>
        /// <returns>The named environment.</returns>
        /// <exception cref="PactmanConfigurationException">The name is not a supported environment.</exception>
        public static PactmanEnvironment ParseEnvironment(string name)
        {
            if (PactmanEnvironments.TryParse(name, out var environment))
            {
                return environment;
            }

            throw new PactmanConfigurationException(string.Format(
                CultureInfo.InvariantCulture,
                "Unknown environment \"{0}\". Supported: {1}. Use BaseUrl to target a host that is not a named environment.",
                name,
                PactmanEnvironments.SupportedNames()));
        }

        private static string ValidateBaseUrl(string baseUrl)
        {
            var trimmed = baseUrl.Trim();

            if (trimmed.Length == 0)
            {
                throw new PactmanConfigurationException("`BaseUrl` must be a non-empty URL string.");
            }

            if (!Uri.TryCreate(trimmed, UriKind.Absolute, out var uri))
            {
                throw new PactmanConfigurationException(string.Format(
                    CultureInfo.InvariantCulture,
                    "`BaseUrl` is not a valid URL: \"{0}\". Expected something like https://entities.pactman.org.",
                    baseUrl));
            }

            if (uri.Scheme != Uri.UriSchemeHttp && uri.Scheme != Uri.UriSchemeHttps)
            {
                throw new PactmanConfigurationException(string.Format(
                    CultureInfo.InvariantCulture,
                    "`BaseUrl` must use http or https, received \"{0}\".",
                    uri.Scheme));
            }

            // Normalized to scheme://authority[/path] with no trailing slash, so joining a
            // path onto it can never produce a double slash.
            var authority = uri.IsDefaultPort
                ? uri.Host
                : string.Format(CultureInfo.InvariantCulture, "{0}:{1}", uri.Host, uri.Port);

            return uri.Scheme + "://" + authority + uri.AbsolutePath.TrimEnd('/');
        }

        private static TimeSpan ResolveTimeout(TimeSpan? timeout)
        {
            if (timeout is null)
            {
                return ClientConfig.DefaultTimeout;
            }

            if (timeout.Value <= TimeSpan.Zero)
            {
                throw new PactmanConfigurationException(
                    "`Timeout` must be greater than zero. There is no way to disable the timeout.");
            }

            return timeout.Value;
        }

        private static double? ResolveRequestsPerSecond(double? value)
        {
            if (value is null)
            {
                return null;
            }

            if (double.IsNaN(value.Value) || double.IsInfinity(value.Value) || value.Value <= 0)
            {
                throw new PactmanConfigurationException(
                    "`MaxRequestsPerSecond` must be a number greater than zero, or omitted.");
            }

            return value;
        }

        /// <summary>
        /// Strips whatever a runtime or OS description might contain that a header cannot.
        /// </summary>
        /// <remarks>
        /// <see cref="RuntimeInformation.OSDescription"/> is free text — on Linux it is the
        /// whole <c>uname</c> line, newlines and all. An unsanitized value here would be a
        /// header-injection seam in every outbound request.
        /// </remarks>
        private static string HeaderSafe(string value)
        {
            var safe = new StringBuilder(value.Length);

            foreach (var character in value)
            {
                if (character >= 0x20 && character < 0x7F && character != '(' && character != ')')
                {
                    safe.Append(character);
                }
                else if (character == ' ' || character == '\t' || character == '\n' || character == '\r')
                {
                    safe.Append(' ');
                }
            }

            var trimmed = safe.ToString().Trim();

            return trimmed.Length == 0 ? "unknown" : trimmed;
        }
    }
}
