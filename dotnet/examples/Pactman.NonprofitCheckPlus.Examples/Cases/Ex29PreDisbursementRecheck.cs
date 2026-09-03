using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using Pactman.NonprofitCheckPlus.Dev;

namespace Pactman.NonprofitCheckPlus.Examples.Cases;

/// <summary>
/// EX-29 — Pre-disbursement recheck.
/// </summary>
/// <remarks>
/// Approval and payment are different moments. This re-checks at the second one and
/// compares the finding against what was recorded at the first.
/// </remarks>
public sealed class Ex29PreDisbursementRecheck : IExample
{
    /// <inheritdoc />
    public string Id => "ex-29";

    /// <inheritdoc />
    public string Title => "Re-check at disbursement and diff against what approval recorded.";

    /// <inheritdoc />
    public async Task RunAsync(string[] args)
    {
        using var context = ExampleContext.WithFixtures();

        // What was stored when the grant was approved, three months ago.
        var atApproval = new Dictionary<string, object?>(StringComparer.Ordinal)
        {
            ["ein"] = Fixtures.Eins.Revoked,
            ["organization_name"] = "LAPSED FILINGS EXAMPLE SOCIETY",
            ["pub78_verified"] = true,
            ["bmf_status"] = true,
            ["revocation_date"] = null,
            ["ofac_status"] = Fixtures.OfacNoMatch,
            ["checked_at"] = "2026-05-01T09:00:00Z",
        };

        Output.Heading("Recorded at approval");

        foreach (var field in atApproval)
        {
            Output.Field(field.Key, field.Value);
        }

        var result = await context.Client.Nonprofits.CheckAsync((string)atApproval["ein"]!);
        var organization = result.Nonprofit;

        if (organization is null)
        {
            // A record that has disappeared is itself a finding, and not one to pay through.
            Output.Heading("At disbursement");
            Output.Field("outcome", "HOLD — the API no longer returns a record for this EIN");

            return;
        }

        var now = new Dictionary<string, object?>(StringComparer.Ordinal)
        {
            ["ein"] = organization.Ein,
            ["organization_name"] = organization.OrganizationName,
            ["pub78_verified"] = organization.Pub78Verified,
            ["bmf_status"] = organization.BmfStatus,
            ["revocation_date"] = organization.RevocationDate,
            ["ofac_status"] = organization.OfacStatus,
            ["checked_at"] = ApiDate.CheckedAt(),
        };

        Output.Heading("At disbursement");

        foreach (var field in now)
        {
            Output.Field(field.Key, field.Value);
        }

        Output.Heading("What changed");

        var changed = new List<string>();

        foreach (var field in atApproval.Keys.Where(key => key != "checked_at"))
        {
            var before = Output.Text(atApproval[field]);
            var after = Output.Text(now[field]);

            if (!string.Equals(before, after, StringComparison.Ordinal))
            {
                changed.Add(field);
                Output.Field(field, $"{Output.Format(atApproval[field])} → {Output.Format(now[field])}");
            }
        }

        if (changed.Count == 0)
        {
            Output.Bullet("Nothing material changed since approval.");
        }

        Output.Heading("The decision");

        // Only some changes matter. A name that gained a comma is not a reason to hold
        // a payment; a revocation that appeared is.
        var material = changed
            .Where(field => field is "pub78_verified" or "bmf_status" or "revocation_date" or "ofac_status")
            .ToList();

        Output.Field("changed", changed.Count == 0 ? "none" : string.Join(", ", changed));
        Output.Field("material", material.Count == 0 ? "none" : string.Join(", ", material));
        Output.Field("outcome", material.Count == 0 ? "RELEASE PAYMENT" : "HOLD — re-approve before paying");

        Output.Note(
            "An approval is a statement about the day it was made. Between approval and\n"
            + "payment an exemption can lapse and a sanctions listing can appear, and the\n"
            + "money moves on the second date, not the first.");
    }
}
