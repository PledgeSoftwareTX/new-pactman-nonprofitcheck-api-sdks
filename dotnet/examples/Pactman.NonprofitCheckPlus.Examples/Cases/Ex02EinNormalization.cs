using System;
using System.Linq;
using System.Threading.Tasks;
using Pactman.NonprofitCheckPlus.Exceptions;

namespace Pactman.NonprofitCheckPlus.Examples.Cases;

/// <summary>
/// EX-02 — EIN normalization.
/// </summary>
/// <remarks>
/// A hyphenated, whitespace-padded EIN normalized to nine digits before the request, with
/// the original kept for diagnostics.
/// </remarks>
public sealed class Ex02EinNormalization : IExample
{
    /// <inheritdoc />
    public string Id => "ex-02";

    /// <inheritdoc />
    public string Title => "Normalize an EIN before the request, keeping the original for diagnostics.";

    /// <inheritdoc />
    public async Task RunAsync(string[] args)
    {
        Output.Heading("Accepted shapes");

        foreach (var candidate in new[] { "411787097", "41-1787097", "  41-1787097  ", "042103594" })
        {
            Output.Field($"\"{candidate}\"", Ein.Normalize(candidate));
        }

        Output.Heading("Rejected shapes");

        foreach (var candidate in new[] { "4117870", "41178709X", "41-178-7097", "" })
        {
            // IsValid never throws, so it is what a form validator wants.
            Output.Field($"\"{candidate}\"", Ein.IsValid(candidate) ? "valid" : "rejected locally");
        }

        Output.Heading("Leading zeros");

        Output.Bullet("042103594 read as an int is 42103594 — a different EIN.");
        Output.Bullet("Keep EINs as strings end to end: spreadsheet columns, JSON, database types.");

        // Whatever the user typed is what the user will recognize in an error message,
        // so keep it beside the normalized form rather than replacing it.
        var submitted = ExampleContext.Argument(args, 0, "  41-1787097 ");
        var normalized = Ein.Normalize(submitted);

        Output.Heading("One lookup");
        Output.Field("as submitted", $"\"{submitted}\"");
        Output.Field("as sent", normalized);

        using var context = ExampleContext.Live();

        try
        {
            var result = await context.Client.Nonprofits.CheckAsync(submitted);

            Output.Field("organization_name", result.Nonprofit?.OrganizationName ?? "(no record)");
        }
        catch (PactmanValidationException error)
        {
            // The issue carries the value as supplied, not the normalized one — so the
            // message names what the user actually typed.
            var issue = error.Issues.FirstOrDefault();

            Output.Field("rejected", issue?.Value ?? submitted);
            Output.Field("because", error.Message);
        }

        Output.Note("Normalization is formatting only. It says nothing about tax-exempt status.");
    }
}
