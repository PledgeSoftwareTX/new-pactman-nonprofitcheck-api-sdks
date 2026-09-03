using System;
using System.Collections.Generic;
using Pactman.NonprofitCheckPlus.Models;

namespace Pactman.NonprofitCheckPlus.Exceptions
{
    /// <summary>
    /// Fields shared by every exception derived from an HTTP response.
    /// </summary>
    /// <remarks>
    /// Collected once by the transport and handed to
    /// <see cref="PactmanApiException.FromStatus"/>.
    /// </remarks>
    public sealed class ApiErrorInit
    {
        /// <summary>Initializes the metadata bundle.</summary>
        /// <param name="status">HTTP status code.</param>
        /// <param name="apiMessage"><c>message</c> from the Pactman response envelope, when present.</param>
        /// <param name="apiCode"><c>code</c> from the Pactman response envelope, when present.</param>
        /// <param name="apiErrors"><c>errors</c> from the envelope, normalized to a list.</param>
        /// <param name="requestId">Correlation identifier from the response headers, when present.</param>
        /// <param name="retryAfter"><c>Retry-After</c>, when the server supplied a valid value.</param>
        /// <param name="raw">The parsed response body, or the raw text when it was not JSON.</param>
        /// <param name="attempts">How many attempts were made before this error was surfaced.</param>
        public ApiErrorInit(
            int status,
            string? apiMessage = null,
            int? apiCode = null,
            IReadOnlyList<ApiErrorDetail>? apiErrors = null,
            string? requestId = null,
            TimeSpan? retryAfter = null,
            ResponseBody? raw = null,
            int attempts = 1)
        {
            Status = status;
            ApiMessage = apiMessage;
            ApiCode = apiCode;
            ApiErrors = apiErrors ?? Array.Empty<ApiErrorDetail>();
            RequestId = requestId;
            RetryAfter = retryAfter;
            Raw = raw ?? ResponseBody.Empty;
            Attempts = attempts;
        }

        /// <summary>HTTP status code.</summary>
        public int Status { get; }

        /// <summary><c>message</c> from the Pactman response envelope, when present.</summary>
        public string? ApiMessage { get; }

        /// <summary><c>code</c> from the Pactman response envelope, when present.</summary>
        public int? ApiCode { get; }

        /// <summary><c>errors</c> from the envelope, normalized to a list.</summary>
        public IReadOnlyList<ApiErrorDetail> ApiErrors { get; }

        /// <summary>Correlation identifier from the response headers, when present.</summary>
        public string? RequestId { get; }

        /// <summary><c>Retry-After</c>, when the server supplied a valid value.</summary>
        public TimeSpan? RetryAfter { get; }

        /// <summary>The parsed response body, or the raw text when it was not JSON.</summary>
        public ResponseBody Raw { get; }

        /// <summary>How many attempts were made before this error was surfaced.</summary>
        public int Attempts { get; }
    }
}
