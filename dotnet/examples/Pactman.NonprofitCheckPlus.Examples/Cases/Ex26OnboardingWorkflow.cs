using System;
using System.Collections.Generic;
using System.Threading.Tasks;
using Pactman.NonprofitCheckPlus.Dev;
using Pactman.NonprofitCheckPlus.Exceptions;
using Pactman.NonprofitCheckPlus.Models;

namespace Pactman.NonprofitCheckPlus.Examples.Cases;

/// <summary>
/// EX-26 — Nonprofit onboarding workflow.
/// </summary>
/// <remarks>
/// One applicant, end to end: validate, look up, read every source, and route — with the
/// evidence recorded rather than the conclusion.
/// </remarks>
public sealed class Ex26OnboardingWorkflow : IExample
{
    /// <inheritdoc />
    public string Id => "ex-26";

    /// <inheritdoc />
    public string Title => "One applicant end to end: validate, look up, read, route, record.";

    /// <inheritdoc />
    public async Task RunAsync(string[] args)
    {
        using var context = ExampleContext.WithFixtures();

        foreach (var ein in new[] { Fixtures.Eins.PublicCharity, Fixtures.Eins.Revoked })
        {
            Output.Heading($"Applicant {ein}");

            // 1. Validate locally. Free, and it keeps a typo from spending quota.
            if (!Ein.IsValid(ein))
            {
                Output.Field("outcome", "REJECT — the EIN is malformed");

                continue;
            }

            SingleCheckResult result;

            try
            {
                result = await context.Client.Nonprofits.CheckAsync(ein);
            }
            catch (PactmanNotFoundException)
            {
                Output.Field("outcome", "REVIEW — no record for this EIN");

                continue;
            }
            catch (PactmanException error)
            {
                // A failure to check is not a failure to qualify. Never let an outage
                // become a decision.
                Output.Field("outcome", $"RETRY LATER — {error.Category.ToWireValue()}: {error.Message}");

                continue;
            }

            if (result.Nonprofit is null)
            {
                Output.Field("outcome", "REVIEW — no record for this EIN");

                continue;
            }

            var organization = result.Nonprofit;

            // 2. Read every source. Each answers a different question, and a finding on
            //    any one of them is a finding.
            var bmf = organization.Bmf();
            var pub78 = organization.Pub78();
            var aroe = organization.Aroe();
            var ofac = organization.Ofac();

            var blockers = new List<string>();
            var reviews = new List<string>();

            if (ofac is null)
            {
                reviews.Add("OFAC was not screened");
            }
            else if (Output.Text(ofac.Status).Contains("UID:", StringComparison.Ordinal))
            {
                blockers.Add("possible OFAC SDN match");
            }

            if (aroe?.RevocationDate is not null && aroe.ReinstatementDate is null)
            {
                blockers.Add("exemption automatically revoked, not reinstated");
            }

            if (bmf is null)
            {
                reviews.Add("no BMF data returned");
            }
            else if (bmf.Status == false)
            {
                blockers.Add("not listed in the IRS Business Master File");
            }

            if (pub78 is null)
            {
                reviews.Add("no Publication 78 data returned");
            }
            else if (pub78.Verified == false)
            {
                reviews.Add("not listed in Publication 78");
            }

            if (organization.IrsBmfPub78Conflict == true)
            {
                reviews.Add("the IRS sources disagree");
            }

            Output.Field("organization", organization.OrganizationName);
            Output.Field("blockers", blockers.Count == 0 ? "none" : string.Join("; ", blockers));
            Output.Field("reviews", reviews.Count == 0 ? "none" : string.Join("; ", reviews));

            Output.Field("outcome", (blockers.Count, reviews.Count) switch
            {
                ( > 0, _) => "DECLINE",
                (0, > 0) => "MANUAL REVIEW",
                _ => "APPROVE",
            });

            // 3. Record the evidence, not the verdict. Six months from now someone will
            //    ask why, and a stored boolean cannot answer.
            Output.Heading("Recorded against the application");
            Output.Field("checked_at", ApiDate.CheckedAt());
            Output.Field("request_id", result.RequestId);
            Output.Field("report_date", organization.ReportDate);
            Output.Field("bmf_status", organization.BmfStatus);
            Output.Field("most_recent_bmf", organization.MostRecentBmf);
            Output.Field("pub78_verified", organization.Pub78Verified);
            Output.Field("most_recent_pub78", organization.MostRecentPub78);
            Output.Field("revocation_date", organization.RevocationDate);
            Output.Field("ofac_status", organization.OfacStatus);
        }

        Output.Note(
            "Store what the API said and when it said it. The routing rules above are this\n"
            + "application's policy; they are not in the SDK, and they should be reviewable\n"
            + "by the people who own the policy.");
    }
}
