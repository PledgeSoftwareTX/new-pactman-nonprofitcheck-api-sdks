using System;
using System.Threading.Tasks;
using Pactman.NonprofitCheckPlus.Dev;

namespace Pactman.NonprofitCheckPlus.Examples.Cases;

/// <summary>
/// EX-08 — Automatic revocation detected.
/// </summary>
/// <remarks>
/// An organization in the IRS Automatic Revocation data, flagged and recorded with its
/// source fields.
/// </remarks>
public sealed class Ex08AutomaticRevocation : IExample
{
    /// <inheritdoc />
    public string Id => "ex-08";

    /// <inheritdoc />
    public string Title => "An organization in the IRS Automatic Revocation data.";

    /// <inheritdoc />
    public async Task RunAsync(string[] args)
    {
        // Production will not produce a revoked organization on request.
        using var context = ExampleContext.WithFixtures();

        var result = await context.Client.Nonprofits.CheckAsync(Fixtures.Eins.Revoked);
        var organization = result.Nonprofit!;

        Output.Heading(Output.Text(organization.OrganizationName));

        var aroe = organization.Aroe();

        if (aroe is null)
        {
            Output.Note("The API returned no automatic-revocation data for this organization.");

            return;
        }

        Output.DisplayField(aroe, "revocation_code");
        Output.DisplayField(aroe, "revocation_date");
        Output.DisplayField(aroe, "reinstatement_date");

        Output.Heading("What the other sources say");
        Output.Field("pub78_verified", organization.Pub78Verified);
        Output.Field("bmf_status", organization.BmfStatus);
        Output.Field("exempt_status_code", organization.ExemptStatusCode);

        // A revocation date with no reinstatement date is the shape that matters. Read
        // both, and never infer one from the other.
        var revoked = aroe.RevocationDate is not null;
        var reinstated = aroe.ReinstatementDate is not null;

        Output.Heading("The finding");
        Output.Field("revoked", revoked);
        Output.Field("reinstated", reinstated);
        Output.Field("routes to", (revoked, reinstated) switch
        {
            (true, false) => "DECLINE — exemption automatically revoked and not reinstated",
            (true, true) => "review — revoked, then reinstated. See EX-09",
            _ => "no revocation finding on this record",
        });

        Output.Heading("What to record");

        // Store the source fields, not your conclusion. A conclusion cannot be re-derived
        // six months later when someone asks why the grant was declined.
        Output.Field("checked_at", ApiDate.CheckedAt());
        Output.Field("revocation_code", aroe.RevocationCode);
        Output.Field("revocation_date", aroe.RevocationDate);
        Output.Field("report_date", organization.ReportDate);

        Output.Note(
            "Automatic revocation is for failing to file for three consecutive years. It is\n"
            + "not a finding of wrongdoing, and an organization can be reinstated.");
    }
}
