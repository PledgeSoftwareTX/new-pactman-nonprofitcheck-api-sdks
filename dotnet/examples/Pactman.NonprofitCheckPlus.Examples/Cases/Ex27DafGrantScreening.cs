using System;
using System.Linq;
using System.Threading.Tasks;
using Pactman.NonprofitCheckPlus.Dev;

namespace Pactman.NonprofitCheckPlus.Examples.Cases;

/// <summary>
/// EX-27 — Donor-advised fund grant screening.
/// </summary>
/// <remarks>
/// The checks a DAF sponsor makes before releasing a grant, and the classification that
/// decides whether expenditure responsibility applies.
/// </remarks>
public sealed class Ex27DafGrantScreening : IExample
{
    /// <inheritdoc />
    public string Id => "ex-27";

    /// <inheritdoc />
    public string Title => "DAF grant screening, including the public-charity distinction.";

    /// <inheritdoc />
    public async Task RunAsync(string[] args)
    {
        using var context = ExampleContext.WithFixtures();

        var candidates = new[]
        {
            Fixtures.Eins.PublicCharity,
            Fixtures.Eins.PrivateFoundation,
            Fixtures.Eins.Revoked,
            Fixtures.Eins.OfacMatch,
        };

        var result = await context.Client.Nonprofits.CheckBulkAsync(candidates);
        var byEin = result.ByEin();

        foreach (var ein in candidates)
        {
            if (!byEin.TryGetValue(ein, out var organization))
            {
                Output.Heading(ein);
                Output.Field("decision", "HOLD — no record returned");

                continue;
            }

            Output.Heading(Output.Text(organization.OrganizationName));

            var pub78 = organization.Pub78();
            var aroe = organization.Aroe();
            var ofac = organization.Ofac();
            var bmf = organization.Bmf();

            // A DAF grant turns on deductibility and on classification, and the two are
            // different questions with different sources.
            var deductible = pub78?.Verified == true;
            var revoked = aroe?.RevocationDate is not null && aroe.ReinstatementDate is null;
            var sanctioned = ofac is not null
                && Output.Text(ofac.Status).Contains("UID:", StringComparison.Ordinal);
            var unscreened = ofac is null;

            Output.Field("Pub 78 verified", pub78?.Verified);
            Output.Field("BMF status", bmf?.Status);
            Output.Field("revoked", revoked);
            Output.Field("OFAC", sanctioned ? "POSSIBLE MATCH" : unscreened ? "not screened" : "no match");
            Output.Field("foundation_type_code", bmf?.FoundationTypeCode);

            Output.Field("expenditure responsibility", bmf?.FoundationTypeCode switch
            {
                "pc" => "not required — public charity",
                "pf" => "REQUIRED — private foundation",
                null => "unknown — classification not returned",
                _ => "unknown classification — ask counsel",
            });

            Output.Field("decision", (sanctioned, revoked, unscreened, deductible) switch
            {
                (true, _, _, _) => "BLOCK — escalate to compliance",
                (_, true, _, _) => "DECLINE — exemption revoked",
                (_, _, true, _) => "HOLD — OFAC screening incomplete",
                (_, _, _, false) => "HOLD — not verified in Publication 78",
                _ => "RELEASE",
            });

            foreach (var entry in organization.OrganizationTypes)
            {
                Output.Field("deductibility limit", entry.DeductibilityLimitation);
            }
        }

        Output.Heading("Envelope");
        Output.Field("checks used this cycle", result.CheckCount);
        Output.Field("not found", string.Join(", ", result.NotFoundEins));

        Output.Note(
            "One bulk call screens the whole grant round. The routing table is this\n"
            + "sponsor's policy; expenditure responsibility is a legal determination and\n"
            + "the API classification is evidence for it, not the answer to it.");
    }
}
