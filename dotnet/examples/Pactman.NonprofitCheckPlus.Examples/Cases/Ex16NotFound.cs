using System;
using System.Threading.Tasks;
using Pactman.NonprofitCheckPlus.Dev;
using Pactman.NonprofitCheckPlus.Exceptions;

namespace Pactman.NonprofitCheckPlus.Examples.Cases;

/// <summary>
/// EX-16 — EIN not found.
/// </summary>
/// <remarks>
/// A well-formed EIN the API has no record for, and why that is not a pass.
/// </remarks>
public sealed class Ex16NotFound : IExample
{
    /// <inheritdoc />
    public string Id => "ex-16";

    /// <inheritdoc />
    public string Title => "A well-formed EIN with no record — an answer, not a pass.";

    /// <inheritdoc />
    public async Task RunAsync(string[] args)
    {
        using var context = ExampleContext.WithFixtures();

        var ein = Fixtures.Eins.NoRecord;

        Output.Heading($"Looking up {ein}");
        Output.Field("locally valid", Ein.IsValid(ein));

        try
        {
            var result = await context.Client.Nonprofits.CheckAsync(ein);

            // Some deployments answer 200 with no data rather than 404. Both mean the
            // same thing and both have to be handled.
            Output.Field("status", result.Status);
            Output.Field("nonprofit", result.Nonprofit is null ? "null" : "returned");
            Output.Field("interpretation", "the API has no record for this EIN");
        }
        catch (PactmanNotFoundException error)
        {
            Output.Field("type", error.GetType().Name);
            Output.Field("category", error.Category.ToWireValue());
            Output.Field("origin", error.Origin.ToWireValue());
            Output.Field("status", error.Status);
            Output.Field("message", error.Message);
            Output.Field("requestId", error.RequestId);

            foreach (var detail in error.ApiErrors)
            {
                Output.Field("api error", $"{detail.Resource}: {detail.Reason}");
            }
        }

        Output.Heading("What not-found does and does not mean");
        Output.Bullet("It means: this EIN is not in the data Pactman holds.");
        Output.Bullet("It does NOT mean: the organization does not exist.");
        Output.Bullet("It does NOT mean: the organization is not tax-exempt.");
        Output.Bullet("It does NOT mean: the EIN is wrong — though it often is.");

        Output.Field("routes to", "manual review — never to automatic approval");

        Output.Note(
            "The most common cause is a transcription error in the EIN itself. The second\n"
            + "most common is an organization too new or too small to appear. Neither is a\n"
            + "reason to approve, and neither is a reason to accuse.");
    }
}
