using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using Pactman.NonprofitCheckPlus.Dev;

namespace Pactman.NonprofitCheckPlus.Examples.Cases;

/// <summary>
/// EX-05 — Validating the returned address.
/// </summary>
/// <remarks>
/// Validate the returned address structurally — present, self-consistent, or neither.
/// Complete is not the same as correct.
/// </remarks>
public sealed class Ex05AddressValidation : IExample
{
    /// <inheritdoc />
    public string Id => "ex-05";

    /// <inheritdoc />
    public string Title => "Check the returned address for presence and self-consistency.";

    /// <summary>Placeholders that are present, non-null, and mean nothing.</summary>
    private static readonly string[] Placeholders = { "n/a", "na", "none", "unknown", "-", "." };

    /// <inheritdoc />
    public async Task RunAsync(string[] args)
    {
        // The inconsistent-address fixture is the point of this example, and production
        // will not produce one on request.
        using var context = ExampleContext.WithFixtures();

        foreach (var ein in new[] { Fixtures.Eins.PublicCharity, Fixtures.Eins.InconsistentAddress })
        {
            var result = await context.Client.Nonprofits.CheckAsync(ein);
            var organization = result.Nonprofit;

            if (organization is null)
            {
                continue;
            }

            Output.Heading(Output.Text(organization.OrganizationName));

            Output.DisplayField(organization, "address_line1");
            Output.DisplayField(organization, "address_line2");
            Output.DisplayField(organization, "city");
            Output.DisplayField(organization, "state");
            Output.DisplayField(organization, "state_name");
            Output.DisplayField(organization, "zip");

            var findings = new List<string>();

            // 1. Presence. A field the API did not return and a field it returned as null
            //    are different facts; neither is an address.
            foreach (var field in new[] { "address_line1", "city", "state", "zip" })
            {
                if (!organization.Has(field))
                {
                    findings.Add($"{field} was not returned");
                }
                else if (string.IsNullOrWhiteSpace(organization.GetString(field)))
                {
                    findings.Add($"{field} is null or empty");
                }
            }

            // 2. Placeholders. Present, non-null, and no more an address than a blank.
            foreach (var field in new[] { "address_line1", "address_line2", "city" })
            {
                var value = organization.GetString(field)?.Trim().ToLowerInvariant();

                if (value is not null && Placeholders.Contains(value, StringComparer.Ordinal))
                {
                    findings.Add($"{field} holds a placeholder");
                }
            }

            // 3. Self-consistency. The state code, the spelled-out state name and the
            //    ZIP prefix all describe the same thing, so they can be held against
            //    each other without any external data.
            var state = organization.State;
            var stateName = organization.StateName;

            if (state is not null && stateName is not null && !StateAgrees(state, stateName))
            {
                findings.Add($"state \"{state}\" and state_name \"{stateName}\" disagree");
            }

            // The Pub 78 copy of the city is a second opinion, free of charge.
            var cities = new[] { organization.City, organization.Pub78City }
                .Where(city => !string.IsNullOrWhiteSpace(city))
                .Select(city => city!.ToUpperInvariant())
                .Distinct(StringComparer.Ordinal)
                .ToList();

            if (cities.Count > 1)
            {
                findings.Add("the sources disagree on the city: " + string.Join(" / ", cities));
            }

            Output.Field("findings", findings.Count == 0 ? "none" : string.Join("; ", findings));
            Output.Field("routes to", findings.Count == 0 ? "accept" : "manual review");
        }

        Output.Note(
            "Structural checks only. That an address is present, non-placeholder and\n"
            + "self-consistent says nothing about whether anyone is there — for that you\n"
            + "need an address verification service, which this API is not.");
    }

    /// <summary>
    /// Whether a two-letter code and a spelled-out name describe the same state.
    /// </summary>
    /// <remarks>
    /// A handful of pairs, enough to make the point. A production check would use a
    /// complete table; the shape of the check is what matters here.
    /// </remarks>
    private static bool StateAgrees(string code, string name)
    {
        var known = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
        {
            ["MA"] = "Massachusetts",
            ["ME"] = "Maine",
            ["NY"] = "New York",
            ["CA"] = "California",
            ["TX"] = "Texas",
        };

        // An unknown code is not a disagreement — it is a table this example does not have.
        return !known.TryGetValue(code, out var expected)
            || string.Equals(expected, name, StringComparison.OrdinalIgnoreCase);
    }
}
