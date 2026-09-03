using System;
using System.Collections.Generic;
using System.Linq;
using System.Text.Json;
using System.Threading.Tasks;
using Pactman.NonprofitCheckPlus.Dev;

namespace Pactman.NonprofitCheckPlus.Examples.Cases;

/// <summary>
/// EX-28 — CRM enrichment.
/// </summary>
/// <remarks>
/// Turning a response into a row, keeping the distinction between "the API said null" and
/// "the API said nothing" all the way into storage.
/// </remarks>
public sealed class Ex28CrmEnrichment : IExample
{
    /// <inheritdoc />
    public string Id => "ex-28";

    /// <inheritdoc />
    public string Title => "Map a response to a CRM row without flattening null into absent.";

    /// <inheritdoc />
    public async Task RunAsync(string[] args)
    {
        using var context = ExampleContext.WithFixtures();

        // The sparse record is the interesting one: several fields are null and two are
        // absent entirely, and a naive mapping loses the difference.
        foreach (var ein in new[] { Fixtures.Eins.PublicCharity, Fixtures.Eins.SparseIdentity })
        {
            var result = await context.Client.Nonprofits.CheckAsync(ein);
            var organization = result.Nonprofit!;

            Output.Heading(Output.Text(organization.OrganizationName));

            // Only the fields the API actually returned are written. A field it did not
            // return is left alone in the CRM rather than overwritten with null — the
            // difference between "we learned it is empty" and "we learned nothing".
            var row = new Dictionary<string, object?>(StringComparer.Ordinal);
            var untouched = new List<string>();

            var mapping = new (string Column, string Field)[]
            {
                ("legal_name", "organization_name"),
                ("trading_name", "organization_name_aka"),
                ("street", "address_line1"),
                ("street_2", "address_line2"),
                ("city", "city"),
                ("state", "state"),
                ("postal_code", "zip"),
                ("irs_subsection", "bmf_subsection"),
                ("irs_ruling_year", "ruling_year"),
                ("pub78_verified", "pub78_verified"),
                ("bmf_listed", "bmf_status"),
                ("ofac_note", "ofac_status"),
            };

            foreach (var (column, field) in mapping)
            {
                if (organization.Has(field))
                {
                    row[column] = organization.Get(field);
                }
                else
                {
                    untouched.Add(column);
                }
            }

            // Provenance travels with the data. Without it, nobody can tell a value
            // checked this morning from one checked two years ago.
            row["pactman_checked_at"] = ApiDate.CheckedAt();
            row["pactman_request_id"] = result.RequestId;
            row["pactman_report_date"] = organization.ReportDate;
            row["irs_bmf_extract"] = organization.MostRecentBmf;
            row["irs_pub78_extract"] = organization.MostRecentPub78;

            Output.Field("columns written", row.Count);
            Output.Field("columns left untouched", untouched.Count == 0 ? "none" : string.Join(", ", untouched));

            Output.Heading("The row");

            foreach (var column in row)
            {
                Output.Field(column.Key, column.Value);
            }

            Output.Heading("Kept whole for re-mapping later");

            // Storing the raw envelope means a mapping bug is fixable without spending
            // quota to fetch everything again.
            Output.Field("raw payload bytes", organization.ToJson().Length);
            Output.Field("field count", organization.Count);
        }

        Output.Note(
            "Write only what the API returned, keep the raw payload, and stamp every row\n"
            + "with when it was checked. All three are what make a re-check comparable to\n"
            + "the one before it — which is EX-29 and EX-30.");
    }
}
