using System;
using System.Text.Json;
using System.Threading.Tasks;

namespace Pactman.NonprofitCheckPlus.Examples.Cases;

/// <summary>
/// EX-03 — Identity lookup.
/// </summary>
/// <remarks>
/// EIN, name, AKA and Pactman profile URL, plus the raw envelope alongside the typed model.
/// </remarks>
public sealed class Ex03IdentityLookup : IExample
{
    /// <inheritdoc />
    public string Id => "ex-03";

    /// <inheritdoc />
    public string Title => "Identity fields, and the raw envelope alongside the typed model.";

    /// <inheritdoc />
    public async Task RunAsync(string[] args)
    {
        using var context = ExampleContext.Live();

        var result = await context.Client.Nonprofits.CheckAsync(
            ExampleContext.Argument(args, 0, "41-1787097"));

        if (result.Nonprofit is null)
        {
            Output.Note("The API returned no record for that EIN. That is an answer, not an error.");

            return;
        }

        var organization = result.Nonprofit;

        Output.Heading("Identity");
        Output.DisplayField(organization, "ein");
        Output.DisplayField(organization, "organization_name");
        Output.DisplayField(organization, "organization_name_aka");
        Output.DisplayField(organization, "pactman_org_url");
        Output.DisplayField(organization, "organization_info_last_modified");

        Output.Heading("The same fields, typed");
        Output.Field("Ein", organization.Ein);
        Output.Field("OrganizationName", organization.OrganizationName);
        Output.Field("OrganizationNameAka", organization.OrganizationNameAka);

        Output.Heading("The envelope around it");
        Output.Field("Status", result.Status);
        Output.Field("RequestId", result.RequestId);
        Output.Field("TimeTakenMs", result.TimeTakenMs);
        Output.Field("CheckCount", result.CheckCount);
        Output.Field("Errors", result.Errors.Count);

        // The parsed body is kept whole, so anything not typed above is still reachable.
        if (result.Raw.IsJson)
        {
            Output.Field("raw.code", result.Raw.Envelope.GetProperty("code").GetRawText());
            Output.Field("raw.message", result.Raw.Envelope.GetProperty("message").GetRawText());
        }

        Output.Heading("Fields the API returned");
        Output.Field("count", organization.Count);
        Output.Field("names", string.Join(", ", organization.FieldNames));

        Output.Note(
            "Typed properties and wire names read the same store. Nothing the API sent is\n"
            + "dropped on the way through.");
    }
}
