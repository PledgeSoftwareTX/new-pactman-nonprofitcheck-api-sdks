using System;
using System.Threading.Tasks;

namespace Pactman.NonprofitCheckPlus.Examples.Cases;

/// <summary>
/// EX-07 — Publication 78 and deductibility.
/// </summary>
/// <remarks>
/// Publication 78 verification and deductibility entries, with a donation policy applied
/// in customer code.
/// </remarks>
public sealed class Ex07Pub78Deductibility : IExample
{
    /// <inheritdoc />
    public string Id => "ex-07";

    /// <inheritdoc />
    public string Title => "Publication 78 verification and deductibility entries.";

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

        var pub78 = organization.Pub78();

        if (pub78 is null)
        {
            Output.Note("The API returned no Publication 78 data for this organization.");

            return;
        }

        Output.Heading("Publication 78");
        Output.DisplayField(pub78, "verified");
        Output.DisplayField(pub78, "organization_name");
        Output.DisplayField(pub78, "ein");
        Output.DisplayField(pub78, "city");
        Output.DisplayField(pub78, "state");
        Output.DisplayField(pub78, "indicator");
        Output.DisplayField(pub78, "church_message");
        Output.DisplayField(pub78, "most_recent");

        Output.Heading("Source organization types");
        Output.DisplayField(pub78, "source_org_type_1");
        Output.DisplayField(pub78, "source_org_type_2");
        Output.DisplayField(pub78, "source_org_type_3");

        Output.Heading("Deductibility entries");

        if (pub78.OrganizationTypes.Count == 0)
        {
            Output.Bullet(
                pub78.Has("organization_types")
                    ? "The API returned the field with no entries."
                    : "The API did not return the field at all.");
        }

        foreach (var entry in pub78.OrganizationTypes)
        {
            Output.Field("status", entry.DeductibilityStatusDescription);
            Output.Field("limitation", entry.DeductibilityLimitation);
            Output.Field("wording", entry.Type);
            Console.WriteLine();
        }

        // The policy is the caller's. The SDK returns what the IRS published; what your
        // organization does about a 30% limitation is not a question the API answers.
        Output.Heading("A donation policy, applied here rather than in the SDK");

        var verified = pub78.Verified == true;
        var limitation = pub78.OrganizationTypes.Count > 0
            ? pub78.OrganizationTypes[0].DeductibilityLimitation
            : null;

        Output.Field("Pub 78 verified", verified);
        Output.Field("first limitation", limitation);
        Output.Field("this application would", (verified, limitation) switch
        {
            (false, _) => "decline the tax-receipt claim and route to review",
            (true, "50%") => "accept, receipting at the public-charity limit",
            (true, not null) => $"accept, receipting at the {limitation} limit",
            _ => "accept, but record that no limitation was published",
        });

        Output.Note(
            "pub78_verified is whether the IRS lists the organization in Publication 78.\n"
            + "It is not a donation decision, and this SDK does not make one.");
    }
}
