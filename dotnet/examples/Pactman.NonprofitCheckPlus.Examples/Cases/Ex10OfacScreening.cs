using System;
using System.Threading.Tasks;
using Pactman.NonprofitCheckPlus.Dev;

namespace Pactman.NonprofitCheckPlus.Examples.Cases;

/// <summary>
/// EX-10 — OFAC screening result.
/// </summary>
/// <remarks>
/// Four distinct OFAC outcomes — no match, match, null, and not screened at all.
/// </remarks>
public sealed class Ex10OfacScreening : IExample
{
    /// <inheritdoc />
    public string Id => "ex-10";

    /// <inheritdoc />
    public string Title => "Four distinct OFAC outcomes, none of them a boolean.";

    /// <inheritdoc />
    public async Task RunAsync(string[] args)
    {
        using var context = ExampleContext.WithFixtures();

        var subjects = new[]
        {
            (Fixtures.Eins.PublicCharity, "a clean screening"),
            (Fixtures.Eins.OfacMatch, "a possible match"),
            (Fixtures.Eins.OfacUnavailable, "the field returned as null"),
            (Fixtures.Eins.SparseIdentity, "the field not returned at all"),
        };

        foreach (var (ein, label) in subjects)
        {
            var result = await context.Client.Nonprofits.CheckAsync(ein);
            var organization = result.Nonprofit!;

            Output.Heading($"{Output.Text(organization.OrganizationName)} — {label}");

            var ofac = organization.Ofac();

            // These four states are genuinely different, and flattening any two of them
            // into "not a match" is how a screening result gets lost.
            if (ofac is null)
            {
                Output.Field("outcome", "OFAC WAS NOT SCREENED — the API returned no OFAC fields");
                Output.Field("routes to", "manual screening — absence is not a clear result");

                continue;
            }

            Output.DisplayField(ofac, "status");
            Output.DisplayField(ofac, "list_published_date");

            var status = ofac.Status;

            Output.Field("outcome", status switch
            {
                null when ofac.Has("status") => "SCREENED, NO RESULT — the field came back null",
                null => "not returned",
                _ when status.Contains("UID:", StringComparison.Ordinal) => "POSSIBLE MATCH",
                _ when status.Contains("NOT included", StringComparison.OrdinalIgnoreCase) => "no match",
                _ => "unrecognized wording — treat as unresolved",
            });

            Output.Field("routes to", status switch
            {
                not null when status.Contains("UID:", StringComparison.Ordinal)
                    => "BLOCK and escalate to compliance",
                not null when status.Contains("NOT included", StringComparison.OrdinalIgnoreCase)
                    => "proceed",
                _ => "manual screening",
            });
        }

        Output.Note(
            "ofac_status is prose, not a flag. This SDK does not parse it into a boolean,\n"
            + "because a wording change would silently flip the answer. The matching above\n"
            + "is caller code, visible and auditable, where a wording change breaks loudly.");
    }
}
