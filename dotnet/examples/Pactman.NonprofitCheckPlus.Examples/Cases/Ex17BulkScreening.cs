using System;
using System.Linq;
using System.Threading.Tasks;
using Pactman.NonprofitCheckPlus.Dev;

namespace Pactman.NonprofitCheckPlus.Examples.Cases;

/// <summary>
/// EX-17 — Bulk screening of a list.
/// </summary>
/// <remarks>
/// Screening a grantee list, iterating organization-level results and reading the response
/// envelope.
/// </remarks>
public sealed class Ex17BulkScreening : IExample
{
    /// <inheritdoc />
    public string Id => "ex-17";

    /// <inheritdoc />
    public string Title => "Screen a grantee list in one request, accounting for every outcome.";

    /// <inheritdoc />
    public async Task RunAsync(string[] args)
    {
        using var context = ExampleContext.WithFixtures();

        var portfolio = new[]
        {
            (Ein: Fixtures.Eins.PublicCharity, Name: "Meals Today"),
            (Ein: Fixtures.Eins.PublicCharitySecond, Name: "Aborjaily"),
            (Ein: Fixtures.Eins.Revoked, Name: "Lapsed Filings"),
            (Ein: Fixtures.Eins.OfacMatch, Name: "Overseas Relief"),
            (Ein: Fixtures.Eins.NoRecord, Name: "Unknown Org"),
        };

        // One bulk request is one round trip and one rate-limit slot. Prefer it to a
        // loop of single checks.
        var result = await context.Client.Nonprofits.CheckBulkAsync(portfolio.Select(entry => entry.Ein));

        Output.Heading("The response envelope");
        Output.Field("Status", result.Status);
        Output.Field("TimeTakenMs", result.TimeTakenMs);
        Output.Field("CheckCount", result.CheckCount);
        Output.Field("Organizations", result.Organizations.Count);
        Output.Field("Errors", result.Errors.Count);
        Output.Field("NotFoundEins", string.Join(", ", result.NotFoundEins));

        // Index by EIN. The response is a set of matched records, not a row-for-row
        // answer to your input list — see EX-18.
        var byEin = result.ByEin();

        Output.Heading("Per-organization findings");

        foreach (var entry in portfolio)
        {
            if (!byEin.TryGetValue(entry.Ein, out var organization))
            {
                // No record returned. That is not a pass.
                Output.Field(entry.Name, "no record returned — route to review");

                continue;
            }

            var bmf = organization.Bmf();
            var pub78 = organization.Pub78();
            var aroe = organization.Aroe();
            var ofac = organization.Ofac();

            Output.Field(entry.Name, string.Format(
                System.Globalization.CultureInfo.InvariantCulture,
                "bmf={0} pub78={1} revoked={2} ofac={3}",
                Output.Format(bmf?.Status),
                Output.Format(pub78?.Verified),
                Output.Format(aroe?.RevocationDate is not null),
                ofac is null
                    ? "not returned"
                    : Output.Text(ofac.Status).Contains("UID:", StringComparison.Ordinal)
                        ? "POSSIBLE MATCH"
                        : "no match"));
        }

        Output.Heading("Item-level errors");

        foreach (var detail in result.Errors)
        {
            Output.Field(
                Output.Text(detail.Resource),
                $"{detail.Reason} (code {Output.Format(detail.Code)}) for {string.Join(", ", detail.Eins)}");
        }

        Output.Note("One request, one round trip, and every outcome accounted for.");
    }
}
