using System;
using System.Threading.Tasks;

namespace Pactman.NonprofitCheckPlus.Examples.Cases;

/// <summary>The shortest useful thing: check one EIN and read the result.</summary>
public sealed class Quickstart : IExample
{
    /// <inheritdoc />
    public string Id => "quickstart";

    /// <inheritdoc />
    public string Title => "Check one EIN and read the result.";

    /// <inheritdoc />
    public async Task RunAsync(string[] args)
    {
        var ein = ExampleContext.Argument(args, 0, "41-1787097");

        using var context = ExampleContext.Live();

        var result = await context.Client.Nonprofits.CheckAsync(ein);

        if (result.Nonprofit is null)
        {
            Console.WriteLine($"The API returned no record for {ein}.");

            return;
        }

        Console.WriteLine(result.Nonprofit.OrganizationName);
        Output.Field("EIN", result.Nonprofit.Ein);
        Output.Field("Pub 78", result.Nonprofit.Pub78Verified);
        Output.Field("BMF", result.Nonprofit.BmfStatus);
        Output.Field("OFAC", result.Nonprofit.OfacStatus);
        Output.Field("Checks used this billing cycle", result.CheckCount);
    }
}
