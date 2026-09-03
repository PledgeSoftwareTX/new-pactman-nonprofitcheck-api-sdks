using System;
using System.Linq;
using System.Threading.Tasks;
using Pactman.NonprofitCheckPlus.Configuration;
using Pactman.NonprofitCheckPlus.Dev;

namespace Pactman.NonprofitCheckPlus.Examples.Cases;

/// <summary>
/// EX-18 — Input order and duplicate EINs.
/// </summary>
/// <remarks>
/// The response is a set, not a row-for-row answer. Pairing positionally is the mistake
/// this example exists to prevent.
/// </remarks>
public sealed class Ex18BulkOrderAndDuplicates : IExample
{
    /// <inheritdoc />
    public string Id => "ex-18";

    /// <inheritdoc />
    public string Title => "Why bulk results must be indexed by EIN, never paired positionally.";

    /// <inheritdoc />
    public async Task RunAsync(string[] args)
    {
        using var context = ExampleContext.WithFixtures();

        // Deliberately out of order, with a duplicate.
        var requested = new[]
        {
            Fixtures.Eins.PublicCharitySecond,
            Fixtures.Eins.PublicCharity,
            Fixtures.Eins.PublicCharitySecond,
        };

        Output.Heading("What was sent");
        Output.Field("order", string.Join(", ", requested));
        Output.Field("count", requested.Length);

        var result = await context.Client.Nonprofits.CheckBulkAsync(requested);

        Output.Heading("What came back");
        Output.Field("order", string.Join(", ", result.Organizations.Select(o => o.Ein)));
        Output.Field("count", result.Organizations.Count);

        Output.Heading("The mistake");

        // This is what a positional pairing would conclude, and it is wrong.
        for (var index = 0; index < requested.Length; index++)
        {
            var paired = index < result.Organizations.Count ? result.Organizations[index] : null;

            Output.Field(
                $"requested[{index}] = {requested[index]}",
                paired is null
                    ? "nothing at that position"
                    : $"would be paired with {paired.Ein} — {(paired.Ein == requested[index] ? "right by luck" : "WRONG")}");
        }

        Output.Heading("The pairing that always holds");

        var byEin = result.ByEin();

        foreach (var ein in requested.Distinct(StringComparer.Ordinal))
        {
            Output.Field(ein, byEin.TryGetValue(ein, out var organization)
                ? Output.Text(organization.OrganizationName)
                : "no record");
        }

        Output.Heading("Duplicates");
        Output.Bullet("Duplicates are sent as supplied by default — each one consumes quota.");
        Output.Bullet("The API matches by set membership, so a repeated EIN comes back once.");
        Output.Bullet("Pass Dedupe = true when you would rather not pay for the repeat.");

        var deduped = await context.Client.Nonprofits.CheckBulkAsync(
            requested,
            new BulkRequestOptions { Dedupe = true });

        Output.Field("with Dedupe", $"{deduped.Organizations.Count} organization(s) returned");

        Output.Note(
            "Never zip the request list against the response list. Index by ein — it is the\n"
            + "only key the API guarantees, and ByEin() does it for you.");
    }
}
