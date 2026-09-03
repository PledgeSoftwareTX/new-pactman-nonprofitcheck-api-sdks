using System;
using System.Linq;
using System.Threading.Tasks;
using Pactman.NonprofitCheckPlus.Configuration;
using Pactman.NonprofitCheckPlus.Dev;

namespace Pactman.NonprofitCheckPlus.Examples.Cases;

/// <summary>A tour of the bulk endpoint in one file: send, index, account, dedupe.</summary>
public sealed class BulkOverview : IExample
{
    /// <inheritdoc />
    public string Id => "bulk";

    /// <inheritdoc />
    public string Title => "The bulk endpoint end to end: send, index, account, dedupe.";

    /// <inheritdoc />
    public async Task RunAsync(string[] args)
    {
        using var context = ExampleContext.WithFixtures();

        var eins = new[]
        {
            Fixtures.Eins.PublicCharity,
            Fixtures.Eins.PublicCharitySecond,
            Fixtures.Eins.NoRecord,
        };

        var result = await context.Client.Nonprofits.CheckBulkAsync(eins);

        Output.Heading("One request, three EINs");
        Output.Field("status", result.Status);
        Output.Field("organizations", result.Organizations.Count);
        Output.Field("notFoundEins", string.Join(", ", result.NotFoundEins));
        Output.Field("checkCount", result.CheckCount);

        Output.Heading("Indexed by EIN");

        var byEin = result.ByEin();

        foreach (var ein in eins)
        {
            Output.Field(ein, byEin.TryGetValue(ein, out var organization)
                ? Output.Text(organization.OrganizationName)
                : "no record");
        }

        Output.Heading("Duplicates");

        var withDuplicates = new[] { eins[0], eins[0], eins[1] };

        var kept = await context.Client.Nonprofits.CheckBulkAsync(withDuplicates);
        var deduped = await context.Client.Nonprofits.CheckBulkAsync(
            withDuplicates,
            new BulkRequestOptions { Dedupe = true });

        Output.Field("sent as supplied", $"{withDuplicates.Length} EINs, {kept.Organizations.Count} returned");
        Output.Field("with Dedupe", $"{deduped.Organizations.Count} returned");

        Output.Note("See EX-17 to EX-21 for each of these in detail.");
    }
}
