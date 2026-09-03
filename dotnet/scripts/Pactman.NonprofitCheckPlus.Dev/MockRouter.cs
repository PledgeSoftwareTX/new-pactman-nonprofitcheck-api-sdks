using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;
using System.Threading;
using System.Threading.Tasks;

namespace Pactman.NonprofitCheckPlus.Dev;

/// <summary>
/// A stand-in for the Nonprofit Check Plus API, so the examples can be run in CI
/// without a real key or network access.
/// </summary>
/// <remarks>
/// Only the two check endpoints are implemented, with the same envelope shape, auth
/// header, batch limit, bulk matching semantics and cumulative check count as the real
/// service. Records come from <see cref="Fixtures"/>.
/// <para>
/// Unlike the PHP SDK's router, which is re-entered per request by PHP's built-in
/// server and keeps its counters in a file, this one lives for the life of the
/// <see cref="MockServer"/> that owns it — so the billing-cycle total and the
/// transient-failure budget are ordinary fields behind a lock.
/// </para>
/// </remarks>
public sealed class MockRouter
{
    private const int MaxBulkEins = 50;
    private const string BulkPath = "/api/entities/nonprofitcheckbulk/v1/us/eins";

    private static readonly Regex SinglePattern =
        new(@"^/api/entities/nonprofitcheck/v1/us/ein/(\d{9})$");

    /// <summary>How long the <c>Slow</c> control EIN holds a response open.</summary>
    private static readonly TimeSpan SlowResponse = TimeSpan.FromSeconds(5);

    /// <summary>How many times the <c>TransientFailure</c> control EIN fails before succeeding.</summary>
    private const int TransientFailures = 2;

    private readonly string _validKey;
    private readonly object _state = new();
    private readonly Random _random = new();

    private int _checksUsedThisCycle;
    private int _transientFailuresLeft = TransientFailures;

    /// <summary>Initializes a router that accepts one API key.</summary>
    /// <param name="validKey">The bearer token the router accepts.</param>
    public MockRouter(string validKey) => _validKey = validKey;

    /// <summary>One canned HTTP response.</summary>
    /// <param name="Status">HTTP status to return.</param>
    /// <param name="Body">The response envelope.</param>
    /// <param name="Headers">Extra headers beyond the defaults.</param>
    public sealed record Response(int Status, JsonObject Body, IReadOnlyDictionary<string, string> Headers);

    /// <summary>Handles one request.</summary>
    /// <param name="method">The HTTP method.</param>
    /// <param name="path">The request path, without the query.</param>
    /// <param name="authorization">The <c>Authorization</c> header, when one was sent.</param>
    /// <param name="rawBody">The request body.</param>
    /// <param name="cancellationToken">Cancels a deliberately slow response.</param>
    /// <returns>The response to write.</returns>
    public async Task<Response> HandleAsync(
        string method,
        string path,
        string? authorization,
        string rawBody,
        CancellationToken cancellationToken = default)
    {
        if (!Authorized(authorization))
        {
            return new Response(
                401,
                new JsonObject
                {
                    ["code"] = 401,
                    ["message"] = "Unauthorized",
                    ["errors"] = new JsonArray
                    {
                        new JsonObject { ["resource"] = "nonprofitcheck", ["reason"] = "Invalid API Key" },
                    },
                    ["data"] = null,
                },
                NoHeaders);
        }

        var single = SinglePattern.Match(path);

        if (method == "GET" && single.Success)
        {
            return await HandleSingleAsync(single.Groups[1].Value, cancellationToken).ConfigureAwait(false);
        }

        if (method == "POST" && path == BulkPath)
        {
            JsonNode? decoded = null;

            if (rawBody.Length > 0)
            {
                try
                {
                    decoded = JsonNode.Parse(rawBody);
                }
                catch (JsonException)
                {
                    decoded = null;
                }
            }

            return HandleBulk(decoded);
        }

        return new Response(
            404,
            new JsonObject { ["code"] = 404, ["message"] = "Not Found", ["errors"] = null, ["data"] = null },
            NoHeaders);
    }

    private async Task<Response> HandleSingleAsync(string ein, CancellationToken cancellationToken)
    {
        if (ein == Fixtures.ControlEins.RateLimited)
        {
            return new Response(
                429,
                ErrorEnvelope(429, "Too Many Requests", ErrorList("nonprofitcheck", "Rate limit exceeded")),
                new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase) { ["Retry-After"] = "1" });
        }

        if (ein == Fixtures.ControlEins.TransientFailure)
        {
            if (TakeTransientFailure())
            {
                return new Response(
                    503,
                    ErrorEnvelope(
                        503,
                        "Service Unavailable",
                        ErrorList("nonprofitcheck", "Upstream temporarily unavailable")),
                    NoHeaders);
            }

            return new Response(
                200,
                Envelope(Fixtures.Organization(Fixtures.Eins.PublicCharity), null, Consume(1)),
                NoHeaders);
        }

        if (ein == Fixtures.ControlEins.Slow)
        {
            await Task.Delay(SlowResponse, cancellationToken).ConfigureAwait(false);

            return new Response(
                200,
                Envelope(Fixtures.Organization(Fixtures.Eins.PublicCharity), null, Consume(1)),
                NoHeaders);
        }

        if (!Fixtures.Has(ein))
        {
            return new Response(
                404,
                ErrorEnvelope(
                    404,
                    "Not Found",
                    ErrorList("nonprofitcheck", "A nonprofit with this EIN does not exist in our records")),
                NoHeaders);
        }

        return new Response(200, Envelope(Fixtures.Organization(ein), null, Consume(1)), NoHeaders);
    }

    private Response HandleBulk(JsonNode? body)
    {
        if (body is not JsonArray array)
        {
            return new Response(
                400,
                ErrorEnvelope(
                    400,
                    "Bad Request",
                    ErrorList(
                        "nonprofitcheckbulk",
                        "The nonprofit check bulk API expects an array of EINs as part of the "
                        + "HTTP POST request body")),
                NoHeaders);
        }

        var eins = array.Select(entry => entry?.GetValue<string>() ?? string.Empty).ToList();

        if (eins.Count > MaxBulkEins)
        {
            return new Response(
                400,
                ErrorEnvelope(
                    400,
                    "Bad Request",
                    ErrorList(
                        "nonprofitcheckbulk",
                        string.Format(
                            CultureInfo.InvariantCulture,
                            "A maximum of {0} EINs can be supplied to the nonprofit check bulk API",
                            MaxBulkEins))),
                NoHeaders);
        }

        // Every submitted EIN is counted, duplicates included.
        Consume(eins.Count);

        // The real service selects with `WHERE ein IN (...)`: duplicates collapse to
        // one row and the result order is the database's, not the request's. Sorting
        // here keeps that difference visible instead of accidentally matching.
        var matched = eins.Distinct(StringComparer.Ordinal).Where(Fixtures.Has).OrderBy(ein => ein, StringComparer.Ordinal).ToList();
        var notFound = eins.Where(ein => !Fixtures.Has(ein)).ToList();

        // Unmatched EINs are refunded, so the count reflects records served.
        var count = Consume(-notFound.Count);

        if (matched.Count == 0)
        {
            return new Response(
                404,
                ErrorEnvelope(
                    404,
                    "Not Found",
                    ErrorList(
                        "nonprofitcheckbulk",
                        "There are no matching nonprofits in our records for this set of EINs"),
                    count),
                NoHeaders);
        }

        JsonArray? errors = null;

        if (notFound.Count > 0)
        {
            var missing = new JsonArray();

            foreach (var ein in notFound)
            {
                missing.Add(ein);
            }

            errors = new JsonArray
            {
                new JsonObject
                {
                    ["resource"] = "nonprofitcheckbulk",
                    ["reason"] = "There are no matching nonprofits in our records for this set of EINs",
                    ["code"] = 404,
                    ["eins"] = missing,
                },
            };
        }

        var data = new JsonArray();

        foreach (var ein in matched)
        {
            data.Add(Fixtures.Organization(ein));
        }

        return new Response(200, Envelope(data, errors, count), NoHeaders);
    }

    /// <summary>The success envelope. <c>nonprofit_check_count</c> is the billing-cycle total.</summary>
    private JsonObject Envelope(JsonNode? data, JsonNode? errors, int checkCount) => new()
    {
        ["code"] = 200,
        ["message"] = "OK",
        ["errors"] = errors,
        ["data"] = data,
        ["timeTaken"] = 2 + _random.Next(0, 41),
        ["nonprofit_check_count"] = checkCount,
    };

    private JsonObject ErrorEnvelope(int code, string message, JsonArray? errors, int? checkCount = null) => new()
    {
        ["code"] = code,
        ["message"] = message,
        ["errors"] = errors,
        ["data"] = null,
        ["timeTaken"] = 1,
        ["nonprofit_check_count"] = checkCount ?? Consume(0),
    };

    private static JsonArray ErrorList(string resource, string reason) => new()
    {
        new JsonObject { ["resource"] = resource, ["reason"] = reason },
    };

    private bool Authorized(string? authorization) =>
        authorization is not null && authorization == "Bearer " + _validKey;

    /// <summary>
    /// Adds a delta to the billing-cycle total and returns the new value.
    /// </summary>
    /// <remarks>A negative delta refunds, which is how unmatched bulk EINs stop counting.</remarks>
    private int Consume(int delta)
    {
        lock (_state)
        {
            _checksUsedThisCycle += delta;

            return _checksUsedThisCycle;
        }
    }

    /// <summary>True while failures remain; resets the budget once it is exhausted.</summary>
    private bool TakeTransientFailure()
    {
        lock (_state)
        {
            if (_transientFailuresLeft > 0)
            {
                _transientFailuresLeft--;

                return true;
            }

            _transientFailuresLeft = TransientFailures;

            return false;
        }
    }

    private static readonly IReadOnlyDictionary<string, string> NoHeaders =
        new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
}
