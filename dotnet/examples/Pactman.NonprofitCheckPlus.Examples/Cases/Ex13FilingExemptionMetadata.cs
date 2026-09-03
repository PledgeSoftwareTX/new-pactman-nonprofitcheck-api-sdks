using System;
using System.Collections.Generic;
using System.Threading.Tasks;

namespace Pactman.NonprofitCheckPlus.Examples.Cases;

/// <summary>
/// EX-13 — Filing and exemption metadata.
/// </summary>
/// <remarks>
/// Filing and exemption codes preserved exactly, or mapped through documented tables with
/// an unknown-value fallback.
/// </remarks>
public sealed class Ex13FilingExemptionMetadata : IExample
{
    /// <inheritdoc />
    public string Id => "ex-13";

    /// <inheritdoc />
    public string Title => "Filing and exemption codes, mapped with an unknown-value fallback.";

    /// <summary>A partial IRS filing-requirement table, as an example of the shape.</summary>
    private static readonly IReadOnlyDictionary<string, string> FilingRequirements =
        new Dictionary<string, string>(StringComparer.Ordinal)
        {
            ["00"] = "No 990 return required",
            ["01"] = "990 (all other) or 990-EZ return",
            ["02"] = "990 — required to file the full return",
            ["03"] = "990 — not required to file (religious organization)",
            ["04"] = "990 — not required to file (government instrumentality)",
            ["06"] = "990 — not required to file (church)",
            ["13"] = "990 — not required to file (religious organization)",
        };

    /// <inheritdoc />
    public async Task RunAsync(string[] args)
    {
        using var context = ExampleContext.Live();

        var result = await context.Client.Nonprofits.CheckAsync(
            ExampleContext.Argument(args, 0, "41-1787097"));

        var organization = result.Nonprofit;

        if (organization is null)
        {
            Output.Note("No record returned.");

            return;
        }

        Output.Heading("As the API sent them");
        Output.DisplayField(organization, "filing_req_code");
        Output.DisplayField(organization, "exempt_status_code");
        Output.DisplayField(organization, "bmf_subsection");
        Output.DisplayField(organization, "group_exemption");

        Output.Heading("Mapped for display");

        var filing = organization.FilingReqCode;

        // Store the code, display the mapping, and never let an unmapped value fall
        // through to a friendly default — "no return required" is the wrong guess to
        // make about an organization whose code you do not recognize.
        Output.Field("filing_req_code", filing);
        Output.Field(
            "means",
            filing is null
                ? "not returned"
                : FilingRequirements.TryGetValue(filing, out var text)
                    ? text
                    : $"code \"{filing}\" is not in this application's table — route to review");

        var groupExemption = organization.GroupExemption;

        // 0000 is the IRS's way of saying "none", not a group whose number is zero.
        Output.Field(
            "group exemption",
            groupExemption switch
            {
                null => "not returned",
                "0000" => "none — the organization holds its own exemption",
                _ => $"subordinate under group ruling {groupExemption}",
            });

        Output.Note(
            "Codes are stable; descriptions are not. Store what the API sent, map it at\n"
            + "display time, and keep the raw code beside anything derived from it.");
    }
}
