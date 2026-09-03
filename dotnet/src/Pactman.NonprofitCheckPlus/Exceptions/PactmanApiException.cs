using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using Pactman.NonprofitCheckPlus.Models;

using Pactman.NonprofitCheckPlus.Internal;

namespace Pactman.NonprofitCheckPlus.Exceptions
{
    /// <summary>
    /// An error returned by the Pactman API.
    /// </summary>
    /// <remarks>
    /// Thrown directly when the status maps to no more specific subclass; response
    /// metadata is preserved even when the body could not be deserialized.
    /// </remarks>
    public class PactmanApiException : PactmanException
    {
        /// <summary>Initializes the exception from response metadata.</summary>
        /// <param name="message">Human-readable description of the failure.</param>
        /// <param name="init">The metadata the transport collected from the response.</param>
        /// <param name="category">The category to report; defaults to <see cref="ErrorCategory.Api"/>.</param>
        /// <exception cref="ArgumentNullException"><paramref name="init"/> is <see langword="null"/>.</exception>
        public PactmanApiException(string message, ApiErrorInit init, ErrorCategory category = ErrorCategory.Api)
            : base(message, category, ErrorOrigin.Api)
        {
            if (init is null)
            {
                throw new ArgumentNullException(nameof(init));
            }

            Status = init.Status;
            ApiMessage = init.ApiMessage;
            ApiCode = init.ApiCode;
            ApiErrors = init.ApiErrors;
            RequestId = init.RequestId;
            RetryAfter = init.RetryAfter;
            Raw = init.Raw;
            Attempts = init.Attempts;
        }

        /// <summary>HTTP status code.</summary>
        public int Status { get; }

        /// <summary><c>message</c> from the Pactman response envelope, when present.</summary>
        public string? ApiMessage { get; }

        /// <summary><c>code</c> from the Pactman response envelope, when present.</summary>
        public int? ApiCode { get; }

        /// <summary>Item-level failures from the envelope's <c>errors</c>.</summary>
        public IReadOnlyList<ApiErrorDetail> ApiErrors { get; }

        /// <summary>Correlation identifier from the response headers, when the server sent one.</summary>
        public string? RequestId { get; }

        /// <summary><c>Retry-After</c>, when the server supplied a valid value.</summary>
        public TimeSpan? RetryAfter { get; }

        /// <summary>The parsed response body, or the raw text when it was not JSON.</summary>
        public ResponseBody Raw { get; }

        /// <summary>How many attempts were made before this error was surfaced.</summary>
        public int Attempts { get; }

        /// <inheritdoc />
        public override IReadOnlyDictionary<string, object?> ToDictionary() =>
            new FieldMap(base.ToDictionary())
            {
                ["status"] = Status,
                ["apiMessage"] = ApiMessage,
                ["apiCode"] = ApiCode,
                ["apiErrors"] = ApiErrors.Select(detail => detail.ToDictionary()).ToList(),
                ["requestId"] = RequestId,
                ["retryAfterSeconds"] = RetryAfter?.TotalSeconds,
                ["attempts"] = Attempts,
            };

        /// <summary>Builds the exception subclass that matches an HTTP status code.</summary>
        /// <param name="init">The metadata the transport collected from the response.</param>
        /// <returns>The most specific exception type for the status.</returns>
        /// <exception cref="ArgumentNullException"><paramref name="init"/> is <see langword="null"/>.</exception>
        public static PactmanApiException FromStatus(ApiErrorInit init)
        {
            if (init is null)
            {
                throw new ArgumentNullException(nameof(init));
            }

            var message = (init.ApiMessage ?? string.Empty).Trim();

            if (message.Length == 0)
            {
                message = DefaultMessageForStatus(init.Status);
            }

            return init.Status switch
            {
                400 => new PactmanBadRequestException(message, init),
                401 => new PactmanAuthenticationException(message, init),
                403 => new PactmanAuthorizationException(message, init),
                404 => new PactmanNotFoundException(message, init),
                429 => new PactmanRateLimitException(message, init),
                >= 500 => new PactmanServerException(message, init),
                _ => new PactmanApiException(message, init),
            };
        }

        private static string DefaultMessageForStatus(int status) => status switch
        {
            400 => "The Pactman API rejected the request.",
            401 => "The Pactman API key was rejected.",
            403 => "This Pactman API key is not permitted to access that resource.",
            404 => "No matching record was found.",
            429 => "The Pactman API rate limit was exceeded.",
            >= 500 => string.Format(
                CultureInfo.InvariantCulture,
                "The Pactman API returned a server error (HTTP {0}).",
                status),
            _ => string.Format(
                CultureInfo.InvariantCulture,
                "The Pactman API returned an unexpected response (HTTP {0}).",
                status),
        };
    }
}
