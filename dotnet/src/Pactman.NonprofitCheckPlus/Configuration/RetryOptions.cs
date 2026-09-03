using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using Pactman.NonprofitCheckPlus.Exceptions;

namespace Pactman.NonprofitCheckPlus.Configuration
{
    /// <summary>
    /// Retry policy. Applied per request, on top of the overall timeout.
    /// </summary>
    /// <remarks>
    /// <para>
    /// Every property carries the SDK default, so <c>new RetryOptions { MaxRetries = 5 }</c>
    /// is a complete policy rather than a patch. To adjust a client's policy for one
    /// request without restating it, use a <c>with</c> expression over the policy in
    /// force: <c>client.Retry with { MaxRetries = 5 }</c>.
    /// </para>
    /// <para>
    /// Values are validated on construction and again on every <c>with</c>, so an
    /// unusable policy fails at the assignment rather than mid-flight on a retry.
    /// </para>
    /// </remarks>
    public sealed record RetryOptions
    {
        /// <summary>Statuses that are never retried, regardless of <see cref="RetryableStatuses"/>.</summary>
        private static readonly int[] NeverRetryStatuses = { 400, 401, 403, 404 };

        private readonly int _maxRetries = 2;
        private readonly TimeSpan _initialDelay = TimeSpan.FromMilliseconds(500);
        private readonly TimeSpan _maxDelay = TimeSpan.FromSeconds(8);
        private readonly double _backoffFactor = 2.0;
        private readonly IReadOnlyList<int> _retryableStatuses = new[] { 429, 500, 502, 503, 504 };

        /// <summary>The SDK's default policy: two retries, jittered exponential backoff.</summary>
        public static RetryOptions Default { get; } = new RetryOptions();

        /// <summary>A policy that never retries.</summary>
        public static RetryOptions None { get; } = new RetryOptions { MaxRetries = 0 };

        /// <summary>
        /// Retries after the first attempt. <c>0</c> disables retrying.
        /// </summary>
        /// <exception cref="PactmanConfigurationException">The value is negative.</exception>
        public int MaxRetries
        {
            get => _maxRetries;
            init
            {
                if (value < 0)
                {
                    throw new PactmanConfigurationException("`MaxRetries` must be 0 or more.");
                }

                _maxRetries = value;
            }
        }

        /// <summary>
        /// Delay before the first retry. Subsequent delays grow by <see cref="BackoffFactor"/>
        /// and are randomized when <see cref="Jitter"/> is on.
        /// </summary>
        /// <exception cref="PactmanConfigurationException">The value is negative.</exception>
        public TimeSpan InitialDelay
        {
            get => _initialDelay;
            init
            {
                if (value < TimeSpan.Zero)
                {
                    throw new PactmanConfigurationException("`InitialDelay` must be 0 or more.");
                }

                _initialDelay = value;
            }
        }

        /// <summary>
        /// Ceiling for a single backoff delay. A server-supplied <c>Retry-After</c> is
        /// honored even when it exceeds this.
        /// </summary>
        /// <exception cref="PactmanConfigurationException">The value is negative.</exception>
        public TimeSpan MaxDelay
        {
            get => _maxDelay;
            init
            {
                if (value < TimeSpan.Zero)
                {
                    throw new PactmanConfigurationException("`MaxDelay` must be 0 or more.");
                }

                _maxDelay = value;
            }
        }

        /// <summary>How much each successive delay grows.</summary>
        /// <exception cref="PactmanConfigurationException">The value is below 1 or not finite.</exception>
        public double BackoffFactor
        {
            get => _backoffFactor;
            init
            {
                if (double.IsNaN(value) || double.IsInfinity(value) || value < 1)
                {
                    throw new PactmanConfigurationException("`BackoffFactor` must be 1 or more.");
                }

                _backoffFactor = value;
            }
        }

        /// <summary>
        /// Randomize each delay across <c>[0, computed]</c> (full jitter) so that clients
        /// failing together do not retry in lockstep.
        /// </summary>
        public bool Jitter { get; init; } = true;

        /// <summary>
        /// HTTP statuses worth retrying.
        /// </summary>
        /// <remarks>
        /// Authentication, authorization, validation and not-found responses are never
        /// retried, whatever this contains.
        /// </remarks>
        /// <exception cref="PactmanConfigurationException">The value is <see langword="null"/>.</exception>
        public IReadOnlyList<int> RetryableStatuses
        {
            get => _retryableStatuses;
            init => _retryableStatuses = value is null
                ? throw new PactmanConfigurationException("`RetryableStatuses` must be a list of status codes.")
                : value.ToArray();
        }

        /// <summary>
        /// Wait for the server's <c>Retry-After</c> before falling back to backoff.
        /// </summary>
        public bool RespectRetryAfter { get; init; } = true;

        /// <summary>True when a status may be retried under this policy.</summary>
        /// <param name="status">The HTTP status the server returned.</param>
        /// <returns><see langword="true"/> when the policy permits another attempt.</returns>
        public bool IsRetryableStatus(int status) =>
            Array.IndexOf(NeverRetryStatuses, status) < 0 && _retryableStatuses.Contains(status);

        /// <summary>A serializable view of the policy.</summary>
        /// <returns>The policy's fields, keyed by name.</returns>
        public IReadOnlyDictionary<string, object?> ToDictionary() =>
            new Dictionary<string, object?>(StringComparer.Ordinal)
            {
                ["maxRetries"] = MaxRetries,
                ["initialDelay"] = InitialDelay.TotalSeconds,
                ["maxDelay"] = MaxDelay.TotalSeconds,
                ["backoffFactor"] = BackoffFactor,
                ["jitter"] = Jitter,
                ["retryableStatuses"] = RetryableStatuses.ToList(),
                ["respectRetryAfter"] = RespectRetryAfter,
            };

        /// <inheritdoc />
        public override string ToString() => string.Format(
            CultureInfo.InvariantCulture,
            "RetryOptions(maxRetries: {0}, initialDelay: {1}s, maxDelay: {2}s, backoffFactor: {3}, jitter: {4})",
            MaxRetries,
            InitialDelay.TotalSeconds,
            MaxDelay.TotalSeconds,
            BackoffFactor,
            Jitter);
    }
}
