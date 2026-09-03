using System;
using System.Globalization;
using System.Linq;
using System.Text.RegularExpressions;
using System.Threading.Tasks;

namespace Pactman.NonprofitCheckPlus.Examples.Cases;

/// <summary>
/// EX-04 — Applicant name comparison.
/// </summary>
/// <remarks>
/// Compare a submitted name with <c>organization_name</c> and <c>organization_name_aka</c>
/// without treating punctuation or abbreviation differences as fraud.
/// </remarks>
public sealed class Ex04NameComparison : IExample
{
    /// <inheritdoc />
    public string Id => "ex-04";

    /// <inheritdoc />
    public string Title => "Compare a submitted name with the IRS record, tolerantly.";

    private static readonly (string Long, string Short)[] Abbreviations =
    {
        ("incorporated", "inc"),
        ("corporation", "corp"),
        ("company", "co"),
        ("association", "assn"),
        ("foundation", "fdn"),
        ("institute", "inst"),
        ("international", "intl"),
        ("society", "soc"),
        ("national", "natl"),
    };

    /// <inheritdoc />
    public async Task RunAsync(string[] args)
    {
        using var context = ExampleContext.Live();

        var ein = ExampleContext.Argument(args, 0, "41-1787097");
        var submitted = ExampleContext.Argument(args, 1, "Meals Today Example Nonprofit, Inc.");

        var result = await context.Client.Nonprofits.CheckAsync(ein);
        var organization = result.Nonprofit;

        if (organization is null)
        {
            Output.Note("No record. There is nothing to compare a name against.");

            return;
        }

        Output.Heading("Names on the record");
        Output.DisplayField(organization, "organization_name");
        Output.DisplayField(organization, "organization_name_aka");
        Output.DisplayField(organization, "pub78_organization_name");
        Output.DisplayField(organization, "bmf_organization_name");

        var candidates = new[]
        {
            ("organization_name", organization.OrganizationName),
            ("organization_name_aka", organization.OrganizationNameAka),
            ("pub78_organization_name", organization.Pub78OrganizationName),
            ("bmf_organization_name", organization.BmfOrganizationName),
        };

        Output.Heading($"Against \"{submitted}\"");

        var best = ("none", 0.0);

        foreach (var (field, value) in candidates)
        {
            if (string.IsNullOrWhiteSpace(value))
            {
                continue;
            }

            var score = Similarity(submitted, value!);
            Output.Field(field, score.ToString("P0", CultureInfo.InvariantCulture));

            if (score > best.Item2)
            {
                best = (field, score);
            }
        }

        Output.Heading("What this does and does not say");
        Output.Field("closest field", best.Item1);
        Output.Field("closest score", best.Item2.ToString("P0", CultureInfo.InvariantCulture));

        // A threshold is a policy decision, so it lives in caller code where it can be
        // argued about — not in the SDK, and not in a score the API never returned.
        Output.Field("routes to", best.Item2 switch
        {
            >= 0.90 => "accept — the names agree",
            >= 0.70 => "manual review — plausibly the same organization",
            _ => "manual review — the names do not look related",
        });

        Output.Note(
            "A name that does not match is not fraud. Organizations file under legal names,\n"
            + "apply under trading names, and the IRS record may be decades old. Compare\n"
            + "against every name the API returned, and route disagreement to a human.");
    }

    /// <summary>
    /// A token-overlap score, tolerant of punctuation, case and common abbreviations.
    /// </summary>
    /// <remarks>
    /// Deliberately crude and deliberately in caller code. The API returns no match score,
    /// and an SDK that invented one would be handing out a number nobody can audit.
    /// </remarks>
    private static double Similarity(string left, string right)
    {
        var a = Tokens(left);
        var b = Tokens(right);

        if (a.Count == 0 || b.Count == 0)
        {
            return 0;
        }

        var shared = a.Intersect(b, StringComparer.Ordinal).Count();

        return (double)shared / Math.Max(a.Count, b.Count);
    }

    private static System.Collections.Generic.HashSet<string> Tokens(string value)
    {
        var normalized = Regex.Replace(value.ToLowerInvariant(), "[^a-z0-9 ]+", " ");

        foreach (var (@long, @short) in Abbreviations)
        {
            normalized = Regex.Replace(normalized, $@"\b{@long}\b", @short);
        }

        return normalized
            .Split(' ', StringSplitOptions.RemoveEmptyEntries)
            .Where(token => token != "the" && token != "of" && token != "and")
            .ToHashSet(StringComparer.Ordinal);
    }
}
