using System;
using System.Threading.Tasks;
using Pactman.NonprofitCheckPlus.Dev;

namespace Pactman.NonprofitCheckPlus.Examples.Cases;

/// <summary>
/// EX-11 — Cross-source conflict.
/// </summary>
/// <remarks>
/// <c>irs_bmf_pub78_conflict</c> handled by recording both sources, not by picking one.
/// </remarks>
public sealed class Ex11SourceConflict : IExample
{
    /// <inheritdoc />
    public string Id => "ex-11";

    /// <inheritdoc />
    public string Title => "A BMF/Pub 78 disagreement, recorded rather than resolved.";

    /// <inheritdoc />
    public async Task RunAsync(string[] args)
    {
        using var context = ExampleContext.WithFixtures();

        var result = await context.Client.Nonprofits.CheckAsync(Fixtures.Eins.Conflicted);
        var organization = result.Nonprofit!;

        Output.Heading(Output.Text(organization.OrganizationName));
        Output.Field("irs_bmf_pub78_conflict", organization.IrsBmfPub78Conflict);

        Output.Heading("What each source says");

        var bmf = organization.Bmf();
        var pub78 = organization.Pub78();

        Output.Field("bmf.status", bmf is null ? Output.NotReturned : Output.Display(bmf, "status"));
        Output.Field("bmf.organization_name", bmf is null ? Output.NotReturned : Output.Display(bmf, "organization_name"));
        Output.Field("bmf.most_recent", bmf is null ? Output.NotReturned : Output.Display(bmf, "most_recent"));

        Output.Field("pub78.verified", pub78 is null ? Output.NotReturned : Output.Display(pub78, "verified"));
        Output.Field("pub78.organization_name", pub78 is null ? Output.NotReturned : Output.Display(pub78, "organization_name"));
        Output.Field("pub78.most_recent", pub78 is null ? Output.NotReturned : Output.Display(pub78, "most_recent"));

        Output.Heading("Handling");

        if (organization.IrsBmfPub78Conflict == true)
        {
            // Both sources are the IRS. Neither is wrong; they were extracted from
            // different files on different days, and the API says so rather than
            // silently preferring one.
            Output.Bullet("The API flagged the disagreement instead of resolving it.");
            Output.Bullet("Record both findings and both extract dates, then route to a human.");
            Output.Bullet("Do NOT write a single derived boolean — it destroys the evidence.");

            Output.Field("routes to", "manual review");
        }
        else
        {
            Output.Field("routes to", "no conflict flagged on this record");
        }

        Output.Heading("What to store");
        Output.Field("checked_at", ApiDate.CheckedAt());
        Output.Field("bmf_status", organization.BmfStatus);
        Output.Field("most_recent_bmf", organization.MostRecentBmf);
        Output.Field("pub78_verified", organization.Pub78Verified);
        Output.Field("most_recent_pub78", organization.MostRecentPub78);
        Output.Field("irs_bmf_pub78_conflict", organization.IrsBmfPub78Conflict);

        Output.Note(
            "Two IRS files disagreeing is ordinary — extracts are cut on different days.\n"
            + "The conflict flag is the API telling you so; picking a winner in code throws\n"
            + "away the one fact a reviewer needs.");
    }
}
