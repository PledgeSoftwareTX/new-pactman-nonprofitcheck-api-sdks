using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using Pactman.NonprofitCheckPlus.Dev;

namespace Pactman.NonprofitCheckPlus.Examples.Cases;

/// <summary>
/// EX-14 — Data freshness and report metadata.
/// </summary>
/// <remarks>
/// Source timestamps, report date and request timing, feeding an application-owned
/// re-review rule.
/// </remarks>
public sealed class Ex14DataFreshness : IExample
{
    /// <inheritdoc />
    public string Id => "ex-14";

    /// <inheritdoc />
    public string Title => "Source timestamps feeding an application-owned re-review rule.";

    /// <summary>How old this application lets a source get before it wants another look.</summary>
    private const int StaleAfterDays = 180;

    /// <inheritdoc />
    public async Task RunAsync(string[] args)
    {
        using var context = ExampleContext.WithFixtures();

        foreach (var ein in new[] { Fixtures.Eins.PublicCharity, Fixtures.Eins.StaleData })
        {
            var result = await context.Client.Nonprofits.CheckAsync(ein);
            var organization = result.Nonprofit!;

            Output.Heading(Output.Text(organization.OrganizationName));

            var sources = new (string Label, string Field)[]
            {
                ("Publication 78 extract", "most_recent_pub78"),
                ("Business Master File extract", "most_recent_bmf"),
                ("Pactman record modified", "organization_info_last_modified"),
                ("Report compiled", "report_date"),
            };

            var stale = new List<string>();
            var unparseable = new List<string>();

            foreach (var (label, field) in sources)
            {
                var raw = organization.GetString(field);
                var age = ApiDate.AgeInDays(raw);

                Output.Field(
                    label,
                    (raw, age) switch
                    {
                        (null, _) when !organization.Has(field) => Output.NotReturned,
                        (null, _) => "null",
                        (_, null) => $"{raw} (could not be parsed)",
                        _ => $"{raw} — {age} days ago",
                    });

                if (raw is not null && age is null)
                {
                    // A date that will not parse is not a fresh date. Say so rather than
                    // treating it as absent and moving on.
                    unparseable.Add(field);
                }
                else if (age > StaleAfterDays)
                {
                    stale.Add(field);
                }
            }

            Output.Field("request timing", $"{result.TimeTakenMs} ms server-side");

            Output.Heading("The re-review rule");
            Output.Field("threshold", $"{StaleAfterDays} days");
            Output.Field("stale sources", stale.Count == 0 ? "none" : string.Join(", ", stale));
            Output.Field("unparseable", unparseable.Count == 0 ? "none" : string.Join(", ", unparseable));
            Output.Field(
                "routes to",
                stale.Count > 0 || unparseable.Count > 0 ? "re-review" : "accept");
        }

        Output.Note(
            "The API publishes when each source was extracted; how old is too old is your\n"
            + "policy, not the SDK's. Note that a fresh report_date over a stale extract\n"
            + "means the report is new and the underlying IRS data is not.");
    }
}
