using System;
using System.Threading.Tasks;
using Pactman.NonprofitCheckPlus.Dev;

namespace Pactman.NonprofitCheckPlus.Examples.Cases;

/// <summary>
/// EX-09 — Revocation with reinstatement.
/// </summary>
/// <remarks>
/// Revocation and reinstatement dates kept separate, and the questions reinstatement does
/// not answer.
/// </remarks>
public sealed class Ex09RevocationReinstatement : IExample
{
    /// <inheritdoc />
    public string Id => "ex-09";

    /// <inheritdoc />
    public string Title => "Revocation and reinstatement dates, kept separate.";

    /// <inheritdoc />
    public async Task RunAsync(string[] args)
    {
        using var context = ExampleContext.WithFixtures();

        foreach (var ein in new[] { Fixtures.Eins.Revoked, Fixtures.Eins.Reinstated })
        {
            var result = await context.Client.Nonprofits.CheckAsync(ein);
            var organization = result.Nonprofit!;
            var aroe = organization.Aroe();

            Output.Heading(Output.Text(organization.OrganizationName));

            if (aroe is null)
            {
                Output.Bullet("No automatic-revocation data returned.");

                continue;
            }

            Output.DisplayField(aroe, "revocation_date");
            Output.DisplayField(aroe, "reinstatement_date");

            var revokedOn = ApiDate.Parse(aroe.RevocationDate);
            var reinstatedOn = ApiDate.Parse(aroe.ReinstatementDate);

            if (revokedOn is not null && reinstatedOn is not null)
            {
                Output.Field("gap in exemption", $"{(reinstatedOn.Value - revokedOn.Value).Days} days");

                // The gap is the part that matters for a donation made in between: a
                // reinstatement is not always retroactive to the revocation date.
                Output.Bullet(
                    "A donation made inside that window may not be deductible even though the\n"
                    + "    organization is exempt today. Reinstatement is not always retroactive.");
            }

            Output.Field("status today", (revokedOn, reinstatedOn) switch
            {
                (not null, null) => "revoked, not reinstated",
                (not null, not null) => "reinstated after revocation",
                _ => "no revocation on record",
            });
        }

        Output.Heading("What reinstatement does not tell you");
        Output.Bullet("Whether the reinstatement was retroactive to the revocation date.");
        Output.Bullet("Whether donations made during the gap are deductible.");
        Output.Bullet("Why the exemption lapsed in the first place.");

        Output.Note(
            "The API returns two dates. Everything above is a question for the organization\n"
            + "or its counsel — the SDK reports the dates and infers nothing from them.");
    }
}
