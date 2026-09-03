using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.Net.Http;
using System.Text;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using Pactman.NonprofitCheckPlus.Configuration;
using Pactman.NonprofitCheckPlus.Exceptions;
using Pactman.NonprofitCheckPlus.Internal;
using Pactman.NonprofitCheckPlus.Models;

namespace Pactman.NonprofitCheckPlus.Http
{
    /// <summary>
    /// HTTP transport: authentication headers, per-attempt deadlines, retries with
    /// jittered backoff, <c>Retry-After</c> handling, and mapping responses to the error
    /// taxonomy.
    /// </summary>
    /// <remarks>
    /// The API key is held in a delegate and written into the <c>Authorization</c> header
    /// at send time. It is never stored as a field, so no diagnostic that walks this
    /// object can reach it.
    /// <para>Internal. Nothing here is part of the public API.</para>
    /// </remarks>
    internal sealed class Transport
    {
        private readonly Func<string> _credential;
        private readonly ClientConfig _config;
        private readonly HttpClient _httpClient;
        private readonly Func<TimeSpan, CancellationToken, Task> _delay;
        private readonly Func<double> _random;
        private readonly Func<double> _monotonic;
        private readonly object _throttleLock = new object();

        private double _nextRequestAt;

        /// <summary>Initializes the transport.</summary>
        /// <param name="credential">Returns the <c>Authorization</c> header value.</param>
        /// <param name="config">The resolved client configuration.</param>
        /// <param name="httpClient">Where to send through.</param>
        /// <param name="hooks">Test seam for the clock. Never set in production.</param>
        internal Transport(
            Func<string> credential,
            ClientConfig config,
            HttpClient httpClient,
            TransportHooks? hooks = null)
        {
            _credential = credential;
            _config = config;
            _httpClient = httpClient;
            _delay = hooks?.Delay ?? ((duration, token) => Task.Delay(duration, token));
            _random = hooks?.Random ?? DefaultRandom;
            _monotonic = hooks?.Monotonic ?? DefaultMonotonic;
        }

        /// <summary>Sends a request, retrying it under the resolved policy.</summary>
        /// <param name="method"><c>GET</c> or <c>POST</c>.</param>
        /// <param name="path">Path to append to the configured base URL.</param>
        /// <param name="body">JSON-encoded when present.</param>
        /// <param name="timeout">Deadline for one attempt; the client's when omitted.</param>
        /// <param name="retry">Policy for this request; the client's when omitted.</param>
        /// <param name="headers">Extra headers. Cannot override <c>Authorization</c>.</param>
        /// <param name="cancellationToken">Bounds the call as a whole, retries included.</param>
        /// <returns>The parsed response.</returns>
        /// <exception cref="PactmanApiException">A non-2xx response the policy will not retry.</exception>
        /// <exception cref="PactmanTimeoutException">The deadline expired on the final attempt.</exception>
        /// <exception cref="PactmanNetworkException">No response was produced on the final attempt.</exception>
        /// <exception cref="OperationCanceledException"><paramref name="cancellationToken"/> was cancelled.</exception>
        internal async Task<TransportResponse> SendAsync(
            HttpMethod method,
            string path,
            IReadOnlyList<string>? body,
            TimeSpan? timeout,
            RetryOptions? retry,
            IReadOnlyDictionary<string, string>? headers,
            CancellationToken cancellationToken)
        {
            var policy = retry ?? _config.Retry;
            var attemptTimeout = timeout ?? _config.Timeout;
            var url = _config.BaseUrl + path;
            var payload = body is null ? null : JsonSerializer.Serialize(body);
            var attempts = 0;

            while (true)
            {
                attempts++;
                cancellationToken.ThrowIfCancellationRequested();
                await ThrottleAsync(cancellationToken).ConfigureAwait(false);

                int status;
                string? requestId;
                ResponseBody parsed;
                TimeSpan? retryAfter;

                try
                {
                    using var attemptCancellation = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
                    attemptCancellation.CancelAfter(attemptTimeout);

                    using var request = BuildRequest(method, url, payload, headers);
                    using var response = await _httpClient
                        .SendAsync(request, HttpCompletionOption.ResponseContentRead, attemptCancellation.Token)
                        .ConfigureAwait(false);

                    status = (int)response.StatusCode;
                    requestId = ReadRequestId(response);
                    retryAfter = ReadRetryAfter(response, DateTimeOffset.UtcNow);
                    parsed = ParseBody(await ReadBodyAsync(response, attemptCancellation.Token).ConfigureAwait(false));
                }
                catch (Exception failure) when (IsTransportFailure(failure, cancellationToken))
                {
                    // The caller's own cancellation surfaces as OperationCanceledException
                    // from the filter above declining it, so "I gave up" never arrives
                    // dressed as "the API was too slow".
                    var error = Classify(failure, attemptTimeout, attempts);

                    if (attempts > policy.MaxRetries)
                    {
                        throw error;
                    }

                    await _delay(ComputeRetryDelay(attempts, policy, null, _random), cancellationToken)
                        .ConfigureAwait(false);

                    continue;
                }

                if (status >= 200 && status < 300)
                {
                    return new TransportResponse(status, requestId, parsed, attempts);
                }

                var apiError = PactmanApiException.FromStatus(BuildApiErrorInit(
                    status: status,
                    parsed: parsed,
                    requestId: requestId,
                    retryAfter: retryAfter,
                    attempts: attempts));

                if (attempts > policy.MaxRetries || !policy.IsRetryableStatus(status))
                {
                    throw apiError;
                }

                await _delay(ComputeRetryDelay(attempts, policy, retryAfter, _random), cancellationToken)
                    .ConfigureAwait(false);
            }
        }

        /// <summary>
        /// Delay before the next attempt.
        /// </summary>
        /// <remarks>
        /// A valid <c>Retry-After</c> wins outright. Otherwise the delay grows
        /// exponentially from <see cref="RetryOptions.InitialDelay"/>, is capped at
        /// <see cref="RetryOptions.MaxDelay"/>, and — with jitter on — is randomized across
        /// the whole range so concurrent clients spread out.
        /// </remarks>
        /// <param name="attempt">Which attempt just failed, counting from one.</param>
        /// <param name="retry">The policy in force.</param>
        /// <param name="retryAfter">The server's <c>Retry-After</c>, when it sent one.</param>
        /// <param name="random">Returns a value in <c>[0, 1)</c>.</param>
        /// <returns>How long to wait before the next attempt.</returns>
        internal static TimeSpan ComputeRetryDelay(
            int attempt,
            RetryOptions retry,
            TimeSpan? retryAfter,
            Func<double>? random = null)
        {
            if (retry.RespectRetryAfter && retryAfter.HasValue && retryAfter.Value >= TimeSpan.Zero)
            {
                return Round(retryAfter.Value);
            }

            var exponential = retry.InitialDelay.TotalSeconds * Math.Pow(retry.BackoffFactor, attempt - 1);
            var capped = Math.Min(exponential, retry.MaxDelay.TotalSeconds);

            if (!retry.Jitter)
            {
                return Round(TimeSpan.FromSeconds(capped));
            }

            random ??= DefaultRandom;

            return Round(TimeSpan.FromSeconds(random() * capped));
        }

        /// <summary>Reads <c>Retry-After</c> as either a delay or an HTTP date.</summary>
        /// <param name="response">The response to read.</param>
        /// <param name="now">The current time, against which a date is measured.</param>
        /// <returns>The delay the server asked for, or <see langword="null"/>.</returns>
        internal static TimeSpan? ReadRetryAfter(HttpResponseMessage response, DateTimeOffset now)
        {
            var retryAfter = response.Headers.RetryAfter;

            if (retryAfter is null)
            {
                return null;
            }

            if (retryAfter.Delta.HasValue)
            {
                return retryAfter.Delta.Value < TimeSpan.Zero ? (TimeSpan?)null : retryAfter.Delta.Value;
            }

            if (retryAfter.Date.HasValue)
            {
                var delta = retryAfter.Date.Value - now;

                return delta < TimeSpan.Zero ? TimeSpan.Zero : delta;
            }

            return null;
        }

        /// <summary>Reads the correlation identifier from the response headers.</summary>
        /// <param name="response">The response to read.</param>
        /// <returns>The first correlation header the server sent, or <see langword="null"/>.</returns>
        internal static string? ReadRequestId(HttpResponseMessage response)
        {
            foreach (var name in new[] { "x-request-id", "x-correlation-id", "request-id" })
            {
                if (response.Headers.TryGetValues(name, out var values))
                {
                    foreach (var value in values)
                    {
                        return value;
                    }
                }
            }

            return null;
        }

        /// <summary>
        /// Parses a response body, preserving unparseable text as evidence.
        /// </summary>
        /// <param name="text">The raw body.</param>
        /// <returns>The parsed JSON, the raw text, or an empty body.</returns>
        internal static ResponseBody ParseBody(string? text)
        {
            if (string.IsNullOrWhiteSpace(text))
            {
                return ResponseBody.Empty;
            }

            JsonElement parsed;

            try
            {
                parsed = JsonValues.Parse(text!);
            }
            catch (JsonException)
            {
                // Preserve whatever the server sent; an unparseable body is still evidence.
                return ResponseBody.FromText(text!);
            }

            // A bare JSON scalar is not an envelope; keep the text as evidence.
            return parsed.ValueKind == JsonValueKind.Object || parsed.ValueKind == JsonValueKind.Array
                ? ResponseBody.FromJson(parsed)
                : ResponseBody.FromText(text!);
        }

        /// <summary>Normalizes the envelope's <c>errors</c> into a list.</summary>
        /// <param name="errors">The envelope's <c>errors</c> value, whatever shape it took.</param>
        /// <returns>The item-level failures, or an empty list.</returns>
        internal static IReadOnlyList<ApiErrorDetail> NormalizeApiErrors(JsonElement? errors)
        {
            var details = new List<ApiErrorDetail>();

            if (!errors.HasValue)
            {
                return details;
            }

            var element = errors.Value;

            switch (element.ValueKind)
            {
                case JsonValueKind.String:
                    var reason = element.GetString();

                    if (!string.IsNullOrWhiteSpace(reason))
                    {
                        details.Add(ApiErrorDetail.FromReason(reason!));
                    }

                    break;

                case JsonValueKind.Array:
                    foreach (var entry in element.EnumerateArray())
                    {
                        if (entry.ValueKind == JsonValueKind.Object)
                        {
                            details.Add(ApiErrorDetail.FromJson(entry));
                        }
                    }

                    break;

                case JsonValueKind.Object:
                    // A single error object, rather than a list of them.
                    details.Add(ApiErrorDetail.FromJson(element));
                    break;

                default:
                    break;
            }

            return details;
        }

        /// <summary>Collects the response metadata an API error carries.</summary>
        /// <param name="status">HTTP status of the response.</param>
        /// <param name="parsed">The parsed body.</param>
        /// <param name="requestId">Correlation identifier, when present.</param>
        /// <param name="retryAfter">The server's <c>Retry-After</c>, when it sent one.</param>
        /// <param name="attempts">How many attempts were made.</param>
        /// <returns>The metadata bundle for an API exception.</returns>
        internal static ApiErrorInit BuildApiErrorInit(
            int status,
            ResponseBody parsed,
            string? requestId,
            TimeSpan? retryAfter,
            int attempts)
        {
            var envelope = parsed.Envelope;
            var hasEnvelope = envelope.ValueKind == JsonValueKind.Object;

            var apiErrors = NormalizeApiErrors(
                hasEnvelope && envelope.TryGetProperty("errors", out var errors) ? errors : (JsonElement?)null);

            var reasons = new List<string>();

            foreach (var detail in apiErrors)
            {
                if (!string.IsNullOrWhiteSpace(detail.Reason))
                {
                    reasons.Add(detail.Reason!);
                }
            }

            string? apiMessage;

            if (reasons.Count > 0)
            {
                apiMessage = string.Join("; ", reasons);
            }
            else if (hasEnvelope
                && envelope.TryGetProperty("message", out var message)
                && message.ValueKind == JsonValueKind.String)
            {
                apiMessage = message.GetString();
            }
            else if (!string.IsNullOrWhiteSpace(parsed.Text))
            {
                var trimmed = parsed.Text!.Trim();
                apiMessage = trimmed.Length > 500 ? trimmed.Substring(0, 500) : trimmed;
            }
            else
            {
                apiMessage = null;
            }

            int? apiCode = null;

            if (hasEnvelope && envelope.TryGetProperty("code", out var code))
            {
                apiCode = JsonValues.AsInt32(code);
            }

            return new ApiErrorInit(
                status: status,
                apiMessage: apiMessage,
                apiCode: apiCode,
                apiErrors: apiErrors,
                requestId: requestId,
                retryAfter: retryAfter,
                raw: parsed,
                attempts: attempts);
        }

        private static bool IsTransportFailure(Exception failure, CancellationToken cancellationToken)
        {
            // A cancellation the caller asked for is theirs to see, untranslated.
            if (cancellationToken.IsCancellationRequested)
            {
                return false;
            }

            return failure is HttpRequestException
                || failure is OperationCanceledException
                || failure is System.IO.IOException;
        }

        private static PactmanException Classify(Exception failure, TimeSpan timeout, int attempts)
        {
            if (failure is OperationCanceledException)
            {
                return new PactmanTimeoutException(
                    string.Format(
                        CultureInfo.InvariantCulture,
                        "The request timed out after {0}s.",
                        timeout.TotalSeconds),
                    timeout,
                    attempts,
                    failure);
            }

            return new PactmanNetworkException(
                "The request to the Pactman API failed: " + failure.Message,
                attempts,
                failure);
        }

        private static TimeSpan Round(TimeSpan value) =>
            TimeSpan.FromMilliseconds(Math.Round(value.TotalMilliseconds));

        private static double DefaultMonotonic() => Stopwatch.GetTimestamp() / (double)Stopwatch.Frequency;

#if NET8_0_OR_GREATER
        private static double DefaultRandom() => System.Random.Shared.NextDouble();
#else
        [ThreadStatic]
        private static Random? _threadRandom;

        private static double DefaultRandom() =>
            (_threadRandom ??= new Random(Guid.NewGuid().GetHashCode())).NextDouble();
#endif

        private static async Task<string> ReadBodyAsync(HttpResponseMessage response, CancellationToken cancellationToken)
        {
#if NET8_0_OR_GREATER
            return await response.Content.ReadAsStringAsync(cancellationToken).ConfigureAwait(false);
#else
            cancellationToken.ThrowIfCancellationRequested();

            return await response.Content.ReadAsStringAsync().ConfigureAwait(false);
#endif
        }

        private HttpRequestMessage BuildRequest(
            HttpMethod method,
            string url,
            string? payload,
            IReadOnlyDictionary<string, string>? perRequest)
        {
            var request = new HttpRequestMessage(method, url);

            if (payload != null)
            {
                request.Content = new StringContent(payload, Encoding.UTF8, "application/json");
            }

            var headers = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);

            foreach (var header in _config.DefaultHeaders)
            {
                headers[header.Key] = header.Value;
            }

            if (perRequest != null)
            {
                foreach (var header in perRequest)
                {
                    headers[header.Key] = header.Value;
                }
            }

            // Set last so neither the client defaults nor a per-request header can
            // displace the credential or misdeclare the payload.
            headers["Accept"] = "application/json";
            headers["User-Agent"] = _config.UserAgent;
            headers["Authorization"] = _credential();

            foreach (var header in headers)
            {
                if (request.Headers.TryAddWithoutValidation(header.Key, header.Value))
                {
                    continue;
                }

                // Content-Type and friends belong on the content, not the request.
                request.Content?.Headers.Remove(header.Key);
                request.Content?.Headers.TryAddWithoutValidation(header.Key, header.Value);
            }

            return request;
        }

        /// <summary>Spaces requests when <see cref="ClientConfig.MaxRequestsPerSecond"/> is configured.</summary>
        private Task ThrottleAsync(CancellationToken cancellationToken)
        {
            var limit = _config.MaxRequestsPerSecond;

            if (limit is null)
            {
                return Task.CompletedTask;
            }

            double wait;

            // A client is meant to be shared across threads, so the schedule is claimed
            // under a lock. The waiting itself happens outside it.
            lock (_throttleLock)
            {
                var interval = 1.0 / limit.Value;
                var now = _monotonic();
                var scheduledAt = Math.Max(now, _nextRequestAt);
                _nextRequestAt = scheduledAt + interval;
                wait = scheduledAt - now;
            }

            return wait > 0 ? _delay(TimeSpan.FromSeconds(wait), cancellationToken) : Task.CompletedTask;
        }
    }
}
