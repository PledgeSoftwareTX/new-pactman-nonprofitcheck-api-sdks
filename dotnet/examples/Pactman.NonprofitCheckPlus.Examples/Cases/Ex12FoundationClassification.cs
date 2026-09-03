using System;
using System.Threading.Tasks;
using Pactman.NonprofitCheckPlus.Dev;

namespace Pactman.NonprofitCheckPlus.Examples.Cases;

/// <summary>
/// EX-12 — Organization type and foundation classification.
/// </summary>
/// <remarks>
/// Organization types, foundation and subsection classification for a grantmaker or DAF
/// display.
/// </remarks>
public sealed class Ex12FoundationClassification : IExample
{
    /// <inheritdoc />
    public string Id => "ex-12";

    /// <inheritdoc />
    public string Title => "Foundation and subsection classification, for a grantmaker display.";

    /// <inheritdoc />
    public async Task RunAsync(string[] args)
    {
        // A public charity and a private foundation side by side: the codes differ, and
        // the difference is what a DAF sponsor needs to see.
        using var context = ExampleContext.WithFixtures();

        foreach (var ein in new[] { Fixtures.Eins.PublicCharity, Fixtures.Eins.PrivateFoundation })
        {
            var result = await context.Client.Nonprofits.CheckAsync(ein);
            var organization = result.Nonprofit!;
            var bmf = organization.Bmf();

            Output.Heading(Output.Text(organization.OrganizationName));

            if (bmf is null)
            {
                Output.Bullet("No BMF data returned; there is nothing to classify.");

                continue;
            }

            Output.DisplayField(bmf, "subsection");
            Output.DisplayField(bmf, "subsection_description");
            Output.DisplayField(bmf, "foundation_code");
            Output.DisplayField(bmf, "foundation_code_description");
            Output.DisplayField(bmf, "foundation_type_code");
            Output.DisplayField(bmf, "foundation_type_description");
            Output.DisplayField(bmf, "foundation_509a_status");
            Output.DisplayField(bmf, "pf_filing_req_cd");

            var pub78 = organization.Pub78();

            Output.Field(
                "pub78 source_org_type_1",
                pub78 is null ? Output.NotReturned : Output.Display(pub78, "source_org_type_1"));

            foreach (var entry in organization.OrganizationTypes)
            {
                Output.Field("deductibility", $"{entry.DeductibilityStatusDescription} / {entry.DeductibilityLimitation}");
            }

            // The description fields are the ones to display. Codes are stable and
            // belong in storage; a description is what a reviewer can read.
            Output.Field("display as", bmf.FoundationTypeDescription ?? bmf.SubsectionDescription ?? "unclassified");

            // A DAF sponsor cares about this distinction, and the API states it — so
            // read the published field rather than inferring from the code.
            Output.Field("grant routing", bmf.FoundationTypeCode switch
            {
                "pc" => "public charity — ordinary DAF grant",
                "pf" => "private foundation — expenditure responsibility may apply",
                null => "unclassified — route to review",
                _ => $"code \"{bmf.FoundationTypeCode}\" — not one this application maps; route to review",
            });
        }

        Output.Note(
            "Store the codes, display the descriptions, and give any unmapped code a\n"
            + "route to review rather than a default. The IRS adds classifications.");
    }
}
