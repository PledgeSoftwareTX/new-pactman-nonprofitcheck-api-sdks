using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Threading.Tasks;
using Pactman.NonprofitCheckPlus.Dev;
using Pactman.NonprofitCheckPlus.Exceptions;

namespace Pactman.NonprofitCheckPlus.Examples.Cases;

/// <summary>
/// EX-20 — Bulk batch limits.
/// </summary>
/// <remarks>
/// The 50-EIN ceiling, why the SDK will not chunk for you, and how to chunk deliberately.
/// </remarks>
public sealed class Ex20BulkBatchLimits : IExample
{
    /// <inheritdoc />
    public string Id => "ex-20";

    /// <inheritdoc />
    public string Title => "The batch ceiling, and chunking a larger list deliberately.";

    /// <inheritdoc />
    public async Task RunAsync(string[] args)
    {
        using var context = ExampleContext.WithFixtures();

        Output.Heading("The limit");
        Output.Field("Endpoints.MaxBulkEins", Endpoints.MaxBulkEins);

        Output.Heading("Over the limit");

        var oversized = Enumerable.Range(0, Endpoints.MaxBulkEins + 1)
            .Select(index => index.ToString("000000000", CultureInfo.InvariantCulture))
            .ToArray();

        try
        {
            await context.Client.Nonprofits.CheckBulkAsync(oversized);

            throw new ExampleFailedException("An oversized batch was accepted. It should have been rejected.");
        }
        catch (PactmanValidationException error)
        {
            // Local, before the request: an oversized batch costs nothing.
            Output.Field("type", error.GetType().Name);
            Output.Field("origin", error.Origin.ToWireValue());
            Output.Field("message", error.Message);
        }

        Output.Heading("Chunking, in caller code");

        // The SDK does not chunk automatically, because chunking decides how much quota
        // a call spends. That is the caller's decision to make and to see in the diff.
        var portfolio = Fixtures.KnownEins.ToList();
        const int batchSize = 5;

        var batches = Chunk(portfolio, batchSize).ToList();

        Output.Field("organizations", portfolio.Count);
        Output.Field("batch size", batchSize);
        Output.Field("requests", batches.Count);

        var matched = 0;
        var missed = new List<string>();

        foreach (var batch in batches)
        {
            var result = await context.Client.Nonprofits.CheckBulkAsync(batch);

            matched += result.Organizations.Count;
            missed.AddRange(result.NotFoundEins);
        }

        Output.Field("matched", matched);
        Output.Field("not found", missed.Count);

        Output.Note(
            "Chunk deliberately, and size the batch against your rate limit rather than\n"
            + "against the maximum. Fifty at a time is allowed; it is not always wise.");
    }

    private static IEnumerable<IReadOnlyList<string>> Chunk(IReadOnlyList<string> items, int size)
    {
        for (var offset = 0; offset < items.Count; offset += size)
        {
            yield return items.Skip(offset).Take(size).ToList();
        }
    }
}
