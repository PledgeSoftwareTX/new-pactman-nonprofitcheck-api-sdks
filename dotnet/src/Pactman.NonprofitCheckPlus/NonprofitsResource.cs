using System;
using System.Collections.Generic;
using System.Globalization;
using System.Net.Http;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using Pactman.NonprofitCheckPlus.Configuration;
using Pactman.NonprofitCheckPlus.Exceptions;
using Pactman.NonprofitCheckPlus.Http;
using Pactman.NonprofitCheckPlus.Internal;
using Pactman.NonprofitCheckPlus.Models;

namespace Pactman.NonprofitCheckPlus
{
    /// <summary>Nonprofit lookups. Reached through <see cref="PactmanClient.Nonprofits"/>.</summary>
    public sealed class NonprofitsResource
    {
        private readonly Transport _transport;

        internal NonprofitsResource(Transport transport) => _transport = transport;

        /// <summary>
        /// Checks a single nonprofit by EIN.
        /// </summary>
        /// <remarks>
        /// <para>
        /// The EIN is normalized and validated locally first; a malformed EIN throws
        /// <see cref="PactmanValidationException"/> without sending a request.
        /// </para>
        /// <code>
        /// var result = await client.Nonprofits.CheckAsync("41-1787097");
        /// Console.WriteLine(result.Nonprofit?.OrganizationName);
        /// </code>
        /// </remarks>
        /// <param name="ein">The EIN to check, hyphenated or not.</param>
        /// <param name="options">Per-request overrides of timeout, retry policy and headers.</param>
        /// <param name="cancellationToken">Bounds the call as a whole, retries included.</param>
        /// <returns>The organization and the envelope metadata that came with it.</returns>
        /// <exception cref="PactmanValidationException">The EIN is malformed. Nothing is sent.</exception>
        /// <exception cref="PactmanException">Any other failure.</exception>
        /// <exception cref="OperationCanceledException"><paramref name="cancellationToken"/> was cancelled.</exception>
        public async Task<SingleCheckResult> CheckAsync(
            string ein,
            RequestOptions? options = null,
            CancellationToken cancellationToken = default)
        {
            var path = Endpoints.SingleCheckPath.Replace("{ein}", Uri.EscapeDataString(Ein.Normalize(ein)));

            var response = await _transport.SendAsync(
                method: HttpMethod.Get,
                path: path,
                body: null,
                timeout: options?.Timeout,
                retry: options?.Retry,
                headers: AsHeaders(options),
                cancellationToken: cancellationToken).ConfigureAwait(false);

            var envelope = response.Body.Envelope;

            return new SingleCheckResult(
                checkCount: ReadCheckCount(envelope),
                timeTakenMs: ReadTimeTaken(envelope),
                errors: ReadErrors(envelope),
                requestId: response.RequestId,
                status: response.Status,
                raw: response.Body,
                nonprofit: ExtractNonprofit(envelope));
        }

        /// <summary>
        /// Checks up to <see cref="Endpoints.MaxBulkEins"/> nonprofits in one request.
        /// </summary>
        /// <remarks>
        /// <para>
        /// Every EIN is normalized and validated before anything is sent; if any one
        /// fails, the whole call throws <see cref="PactmanValidationException"/> identifying
        /// the offending index, and no request is made. EINs are sent in the order supplied
        /// and duplicates are kept unless <see cref="BulkRequestOptions.Dedupe"/> is set —
        /// but the API matches by set membership, so the response is not ordered to match
        /// and a repeated EIN comes back once. Index the results with
        /// <see cref="BulkCheckResult.ByEin"/> rather than pairing positionally.
        /// </para>
        /// <para>
        /// EINs the API has no record for are not an error: they arrive as HTTP 200 with
        /// the missing values in <see cref="BulkCheckResult.NotFoundEins"/>.
        /// </para>
        /// <code>
        /// var result = await client.Nonprofits.CheckBulkAsync(new[] { "41-1787097", "996589560" });
        /// foreach (var organization in result.Organizations)
        /// {
        ///     Console.WriteLine(organization.Ein);
        /// }
        /// </code>
        /// </remarks>
        /// <param name="eins">The EINs to check, hyphenated or not.</param>
        /// <param name="options">Per-request overrides, plus <see cref="BulkRequestOptions.Dedupe"/>.</param>
        /// <param name="cancellationToken">Bounds the call as a whole, retries included.</param>
        /// <returns>The matched organizations and the EINs that missed.</returns>
        /// <exception cref="PactmanValidationException">
        /// The batch is empty, over the limit, or contains a malformed EIN. Nothing is sent.
        /// </exception>
        /// <exception cref="PactmanException">Any other failure.</exception>
        /// <exception cref="OperationCanceledException"><paramref name="cancellationToken"/> was cancelled.</exception>
        public async Task<BulkCheckResult> CheckBulkAsync(
            IEnumerable<string> eins,
            BulkRequestOptions? options = null,
            CancellationToken cancellationToken = default)
        {
            var payload = BuildBulkPayload(eins, options?.Dedupe ?? false);

            var response = await _transport.SendAsync(
                method: HttpMethod.Post,
                path: Endpoints.BulkCheckPath,
                body: payload,
                timeout: options?.Timeout,
                retry: options?.Retry,
                headers: AsHeaders(options),
                cancellationToken: cancellationToken).ConfigureAwait(false);

            var envelope = response.Body.Envelope;
            var errors = ReadErrors(envelope);

            return new BulkCheckResult(
                checkCount: ReadCheckCount(envelope),
                timeTakenMs: ReadTimeTaken(envelope),
                errors: errors,
                requestId: response.RequestId,
                status: response.Status,
                raw: response.Body,
                organizations: ExtractOrganizations(envelope),
                notFoundEins: ExtractNotFoundEins(errors));
        }

        private static IReadOnlyDictionary<string, string>? AsHeaders(RequestOptions? options) =>
            options is null || options.Headers.Count == 0
                ? null
                : new Dictionary<string, string>(options.Headers, StringComparer.OrdinalIgnoreCase);

        private static IReadOnlyList<string> BuildBulkPayload(IEnumerable<string> eins, bool dedupe)
        {
            if (eins is null)
            {
                throw new PactmanValidationException("CheckBulkAsync requires at least one EIN.");
            }

            var normalized = Ein.NormalizeMany(eins);

            if (normalized.Count == 0)
            {
                throw new PactmanValidationException("CheckBulkAsync requires at least one EIN.");
            }

            IReadOnlyList<string> payload = normalized;

            if (dedupe)
            {
                var seen = new HashSet<string>(StringComparer.Ordinal);
                var unique = new List<string>(normalized.Count);

                foreach (var ein in normalized)
                {
                    if (seen.Add(ein))
                    {
                        unique.Add(ein);
                    }
                }

                payload = unique;
            }

            if (payload.Count > Endpoints.MaxBulkEins)
            {
                throw new PactmanValidationException(string.Format(
                    CultureInfo.InvariantCulture,
                    "CheckBulkAsync accepts at most {0} EINs per request, received {1}. Split the input into "
                    + "batches; this SDK does not chunk automatically.",
                    Endpoints.MaxBulkEins,
                    payload.Count));
            }

            return payload;
        }

        private static int? ReadCheckCount(JsonElement envelope) =>
            envelope.ValueKind == JsonValueKind.Object
                && envelope.TryGetProperty("nonprofit_check_count", out var value)
                ? JsonValues.AsInt32(value)
                : null;

        private static double? ReadTimeTaken(JsonElement envelope) =>
            envelope.ValueKind == JsonValueKind.Object && envelope.TryGetProperty("timeTaken", out var value)
                ? JsonValues.AsDouble(value)
                : null;

        private static IReadOnlyList<ApiErrorDetail> ReadErrors(JsonElement envelope) =>
            Transport.NormalizeApiErrors(
                envelope.ValueKind == JsonValueKind.Object && envelope.TryGetProperty("errors", out var value)
                    ? value
                    : (JsonElement?)null);

        private static Nonprofit? ExtractNonprofit(JsonElement envelope)
        {
            if (envelope.ValueKind != JsonValueKind.Object || !envelope.TryGetProperty("data", out var data))
            {
                return null;
            }

            if (data.ValueKind == JsonValueKind.Object)
            {
                return data.EnumerateObject().MoveNext() ? new Nonprofit(data) : null;
            }

            if (data.ValueKind == JsonValueKind.Array)
            {
                foreach (var entry in data.EnumerateArray())
                {
                    return entry.ValueKind == JsonValueKind.Object ? new Nonprofit(entry) : null;
                }
            }

            return null;
        }

        /// <summary>
        /// The published schema returns <c>data</c> as an array. Some deployments wrap it
        /// as <c>{"organizations": [...]}</c>, so both are accepted rather than silently
        /// yielding an empty list.
        /// </summary>
        private static IReadOnlyList<Nonprofit> ExtractOrganizations(JsonElement envelope)
        {
            var organizations = new List<Nonprofit>();

            if (envelope.ValueKind != JsonValueKind.Object || !envelope.TryGetProperty("data", out var data))
            {
                return organizations;
            }

            if (data.ValueKind == JsonValueKind.Object
                && data.TryGetProperty("organizations", out var wrapped)
                && wrapped.ValueKind == JsonValueKind.Array)
            {
                data = wrapped;
            }

            if (data.ValueKind != JsonValueKind.Array)
            {
                return organizations;
            }

            foreach (var entry in data.EnumerateArray())
            {
                if (entry.ValueKind == JsonValueKind.Object)
                {
                    organizations.Add(new Nonprofit(entry));
                }
            }

            return organizations;
        }

        private static IReadOnlyList<string> ExtractNotFoundEins(IReadOnlyList<ApiErrorDetail> errors)
        {
            var missing = new List<string>();

            foreach (var detail in errors)
            {
                foreach (var ein in detail.Eins)
                {
                    missing.Add(ein);
                }
            }

            return missing;
        }
    }
}
