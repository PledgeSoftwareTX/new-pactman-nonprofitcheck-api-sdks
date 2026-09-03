using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Threading.Tasks;
using Pactman.NonprofitCheckPlus.Dev;
using Pactman.NonprofitCheckPlus.Exceptions;

namespace Pactman.NonprofitCheckPlus.Examples.Cases;

/// <summary>
/// EX-30 — Portfolio re-verification.
/// </summary>
/// <remarks>
/// A scheduled sweep over a whole portfolio: chunked, throttled, tolerant of a failed
/// batch, and reporting what moved rather than re-stating what did not.
/// </remarks>
public sealed class Ex30PortfolioReverification : IExample
{
    /// <inheritdoc />
    public string Id => "ex-30";

    /// <inheritdoc />
    public string Title => "A scheduled portfolio sweep: chunked, throttled, fault-tolerant.";

    private const int BatchSize = 4;
    private const int StaleAfterDays = 180;

    /// <inheritdoc />
    public async Task RunAsync(string[] args)
    {
        using var context = ExampleContext.WithFixtures();

        // A ceiling well under the server's, because a nightly sweep has all night and
        // no reason to compete with live traffic for the rate limit.
        using var client = context.Sibling(maxRequestsPerSecond: 10);

        var portfolio = Fixtures.KnownEins.OrderBy(ein => ein, StringComparer.Ordinal).ToList();

        Output.Heading("The sweep");
        Output.Field("organizations", portfolio.Count);
        Output.Field("batch size", BatchSize);
        Output.Field("ceiling", "10 requests/second");

        var findings = new List<(string Ein, string Finding)>();
        var missing = new List<string>();
        var failed = new List<string>();
        var stale = new List<string>();

        foreach (var batch in Chunk(portfolio, BatchSize))
        {
            try
            {
                var result = await client.Nonprofits.CheckBulkAsync(batch);
                var byEin = result.ByEin();

                missing.AddRange(result.NotFoundEins);

                foreach (var ein in batch)
                {
                    if (!byEin.TryGetValue(ein, out var organization))
                    {
                        continue;
                    }

                    var aroe = organization.Aroe();
                    var ofac = organization.Ofac();
                    var pub78 = organization.Pub78();

                    if (ofac is null)
                    {
                        findings.Add((ein, "OFAC not screened"));
                    }
                    else if (Output.Text(ofac.Status).Contains("UID:", StringComparison.Ordinal))
                    {
                        findings.Add((ein, "possible OFAC match"));
                    }

                    if (aroe?.RevocationDate is not null && aroe.ReinstatementDate is null)
                    {
                        findings.Add((ein, "exemption revoked"));
                    }

                    if (pub78?.Verified == false)
                    {
                        findings.Add((ein, "not in Publication 78"));
                    }

                    if (organization.IrsBmfPub78Conflict == true)
                    {
                        findings.Add((ein, "IRS sources disagree"));
                    }

                    var age = ApiDate.AgeInDays(organization.MostRecentBmf);

                    if (age > StaleAfterDays)
                    {
                        stale.Add(ein);
                    }
                }
            }
            catch (PactmanException error)
            {
                // One failed batch is not a failed sweep. Record which organizations
                // were not reached and carry on — a run that aborts on the first error
                // leaves the rest of the portfolio unchecked and nobody the wiser.
                failed.AddRange(batch);

                Output.Field(
                    "batch failed",
                    $"{string.Join(", ", batch)} — {error.Category.ToWireValue()}: {error.Message}");
            }
        }

        Output.Heading("Findings");

        foreach (var (ein, finding) in findings)
        {
            Output.Field(ein, finding);
        }

        if (findings.Count == 0)
        {
            Output.Bullet("None.");
        }

        Output.Heading("Summary");
        Output.Field("checked", portfolio.Count - failed.Count);
        Output.Field("findings", findings.Count);
        Output.Field("organizations with a finding", findings.Select(f => f.Ein).Distinct(StringComparer.Ordinal).Count());
        Output.Field("no record", missing.Count == 0 ? "none" : string.Join(", ", missing.Distinct(StringComparer.Ordinal)));
        Output.Field("stale data", stale.Count == 0 ? "none" : string.Join(", ", stale.Distinct(StringComparer.Ordinal)));
        Output.Field("not reached", failed.Count == 0 ? "none" : string.Join(", ", failed));
        Output.Field("swept at", ApiDate.CheckedAt());

        Output.Note(
            "Report what moved, not the whole portfolio — a nightly mail that lists two\n"
            + "hundred unchanged organizations is a mail nobody opens. Organizations that\n"
            + "could not be reached belong in the report too: an unchecked organization is\n"
            + "not a clean one.");
    }

    private static IEnumerable<IReadOnlyList<string>> Chunk(IReadOnlyList<string> items, int size)
    {
        for (var offset = 0; offset < items.Count; offset += size)
        {
            yield return items.Skip(offset).Take(size).ToList();
        }
    }
}
