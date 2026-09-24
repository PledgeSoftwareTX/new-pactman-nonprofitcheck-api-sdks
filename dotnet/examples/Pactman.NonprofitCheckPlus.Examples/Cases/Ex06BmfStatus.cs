using System;
using System.Threading.Tasks;

namespace Pactman.NonprofitCheckPlus.Examples.Cases;

/// <summary>
/// EX-06 — IRS Business Master File status.
/// </summary>
/// <remarks>
/// Every IRS Business Master File field on the response — status, identity, subsection,
/// exemption, ruling, foundation.
/// </remarks>
public sealed class Ex06BmfStatus : IExample
{
    /// <inheritdoc />
    public string Id => "ex-06";

    /// <inheritdoc />
    public string Title => "Every Business Master File field, read through the grouped view.";

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

        // A null view means the API returned no BMF data at all — which is not the same
        // as bmf_status being false, and must not be collapsed into it.
        var bmf = organization.Bmf();

        if (bmf is null)
        {
            Output.Note(
                "The API returned no Business Master File data for this organization.\n"
                + "That is not the same as \"not in the BMF\". Route it to review.");

            return;
        }

        Output.Heading("Status");
        Output.DisplayField(bmf, "status");
        Output.DisplayField(bmf, "church_message");

        Output.Heading("Identity as the BMF records it");
        Output.DisplayField(bmf, "organization_name");
        Output.DisplayField(bmf, "ein");

        Output.Heading("Exemption");
        Output.DisplayField(bmf, "subsection");
        Output.DisplayField(bmf, "subsection_description");
        Output.DisplayField(bmf, "exempt_status_code");
        Output.DisplayField(bmf, "filing_req_code");
        Output.DisplayField(bmf, "group_exemption");

        Output.Heading("Ruling and classification");
        Output.DisplayField(bmf, "ruling_month");
        Output.DisplayField(bmf, "ruling_year");
        Output.DisplayField(bmf, "foundation_code");
        Output.DisplayField(bmf, "foundation_code_description");
        Output.DisplayField(bmf, "foundation_type_code");
        Output.DisplayField(bmf, "foundation_type_description");
        Output.DisplayField(bmf, "foundation_509a_status");

        Output.Heading("Freshness");
        Output.DisplayField(bmf, "most_recent");

        Output.Note(
            "bmf_status is the IRS's answer about the BMF and nothing else. Publication 78,\n"
            + "automatic revocation and OFAC are separate sources with separate answers.");
    }
}
