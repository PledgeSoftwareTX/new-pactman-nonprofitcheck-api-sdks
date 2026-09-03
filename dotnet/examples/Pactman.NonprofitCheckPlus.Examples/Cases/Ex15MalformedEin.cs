using System;
using System.Linq;
using System.Threading.Tasks;
using Pactman.NonprofitCheckPlus.Exceptions;

namespace Pactman.NonprofitCheckPlus.Examples.Cases;

/// <summary>
/// EX-15 — Malformed EIN rejected locally.
/// </summary>
/// <remarks>
/// A malformed EIN never reaches the network, never spends quota, and reports which item
/// failed and why.
/// </remarks>
public sealed class Ex15MalformedEin : IExample
{
    /// <inheritdoc />
    public string Id => "ex-15";

    /// <inheritdoc />
    public string Title => "A malformed EIN rejected before the request, spending nothing.";

    /// <inheritdoc />
    public async Task RunAsync(string[] args)
    {
        using var context = ExampleContext.Live();

        Output.Heading("A single malformed EIN");

        try
        {
            await context.Client.Nonprofits.CheckAsync("not-an-ein");

            throw new ExampleFailedException("A malformed EIN was accepted. It should have been rejected.");
        }
        catch (PactmanValidationException error)
        {
            Output.Field("type", error.GetType().Name);
            Output.Field("category", error.Category.ToWireValue());

            // Local, not api: nothing was sent, so nothing was billed and there is no
            // request id to chase.
            Output.Field("origin", error.Origin.ToWireValue());
            Output.Field("message", error.Message);

            var issue = error.Issues.Single();
            Output.Field("issue.index", issue.Index);
            Output.Field("issue.value", issue.Value);
        }

        Output.Heading("A batch where some are malformed");

        try
        {
            await context.Client.Nonprofits.CheckBulkAsync(
                new[] { "41-1787097", "nope", "996589560", "12345" });

            throw new ExampleFailedException("A malformed batch was accepted. It should have been rejected.");
        }
        catch (PactmanValidationException error)
        {
            // Every failure at once. A caller fixes the whole batch in one pass rather
            // than one item per round trip.
            Output.Field("message", error.Message);

            foreach (var issue in error.Issues)
            {
                Output.Field($"index {issue.Index}", $"{issue.Value} — {issue.Message}");
            }
        }

        Output.Heading("Asking without throwing");

        foreach (var candidate in new[] { "41-1787097", "nope" })
        {
            Output.Field(candidate, Ein.IsValid(candidate) ? "valid" : "invalid");
        }

        Output.Note(
            "Validation is local and free. It is also formatting-only: a well-formed EIN\n"
            + "may still have no record, which is EX-16 and a different thing entirely.");
    }
}
