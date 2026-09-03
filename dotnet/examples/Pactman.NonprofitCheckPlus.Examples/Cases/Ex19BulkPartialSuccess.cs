using System;
using System.Linq;
using System.Threading.Tasks;
using Pactman.NonprofitCheckPlus.Dev;

namespace Pactman.NonprofitCheckPlus.Examples.Cases;

/// <summary>
/// EX-19 — Partial success and item-level errors.
/// </summary>
/// <remarks>
/// A bulk request where some EINs miss is HTTP 200 with the misses in the envelope's
/// <c>errors</c> — a success that a caller checking only the status code would misread.
/// </remarks>
public sealed class Ex19BulkPartialSuccess : IExample
{
    /// <inheritdoc />
    public string Id => "ex-19";

    /// <inheritdoc />
    public string Title => "Partial success: HTTP 200 carrying item-level failures.";

    /// <inheritdoc />
    public async Task RunAsync(string[] args)
    {
        using var context = ExampleContext.WithFixtures();

        var requested = new[]
        {
            Fixtures.Eins.PublicCharity,
            Fixtures.Eins.NoRecord,
            Fixtures.Eins.PublicCharitySecond,
        };

        var result = await context.Client.Nonprofits.CheckBulkAsync(requested);

        Output.Heading("A successful response with failures inside it");
        Output.Field("HTTP status", result.Status);
        Output.Field("threw", "no — this is a success");
        Output.Field("requested", requested.Length);
        Output.Field("matched", result.Organizations.Count);
        Output.Field("not found", result.NotFoundEins.Count);

        Output.Heading("The item-level errors");

        foreach (var detail in result.Errors)
        {
            Output.Field("resource", detail.Resource);
            Output.Field("reason", detail.Reason);
            Output.Field("code", detail.Code);
            Output.Field("eins", string.Join(", ", detail.Eins));

            // The entry exactly as the API sent it, including anything not typed above.
            Output.Field("raw keys", string.Join(", ", detail.ToDictionary().Keys));
        }

        Output.Heading("Accounting for every input");

        var byEin = result.ByEin();

        foreach (var ein in requested)
        {
            Output.Field(ein, byEin.ContainsKey(ein)
                ? "matched"
                : result.NotFoundEins.Contains(ein, StringComparer.Ordinal)
                    ? "reported not found"
                    : "UNACCOUNTED FOR — investigate");
        }

        // Every input should land in exactly one bucket. An input in neither means the
        // API returned something this code does not understand, and that is worth
        // failing loudly over rather than quietly dropping.
        var unaccounted = requested
            .Where(ein => !byEin.ContainsKey(ein) && !result.NotFoundEins.Contains(ein, StringComparer.Ordinal))
            .ToList();

        Output.Field("unaccounted", unaccounted.Count == 0 ? "none" : string.Join(", ", unaccounted));

        Output.Note(
            "Checking only the HTTP status would read this as a clean pass over three\n"
            + "organizations. It is a clean pass over two, and a miss on the third.");
    }
}
