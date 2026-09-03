using System;
using System.Linq;
using System.Text.Json;
using System.Threading.Tasks;
using Pactman.NonprofitCheckPlus.Dev;

namespace Pactman.NonprofitCheckPlus.Examples.Cases;

/// <summary>
/// EX-25 — Raw response and forward compatibility.
/// </summary>
/// <remarks>
/// A response from a newer API version than this SDK: unknown fields, an unknown member
/// inside a known object, and an enum value outside the documented set. None of it is an
/// error, and none of it is dropped.
/// </remarks>
public sealed class Ex25RawAndForwardCompat : IExample
{
    /// <inheritdoc />
    public string Id => "ex-25";

    /// <inheritdoc />
    public string Title => "Fields newer than this SDK, readable without an upgrade.";

    /// <inheritdoc />
    public async Task RunAsync(string[] args)
    {
        using var context = ExampleContext.WithFixtures();

        var result = await context.Client.Nonprofits.CheckAsync(Fixtures.Eins.FutureFields);
        var organization = result.Nonprofit!;

        Output.Heading("The record parsed without complaint");
        Output.Field("status", result.Status);
        Output.Field("organization_name", organization.OrganizationName);
        Output.Field("fields returned", organization.Count);

        // What this SDK version predicts, read from the contract shipped inside it.
        var known = Fixtures.KnownNonprofitFields().ToHashSet(StringComparer.Ordinal);
        var unknown = organization.FieldNames.Where(field => !known.Contains(field)).ToList();

        Output.Heading("Fields newer than this SDK");

        foreach (var field in unknown)
        {
            Output.Field(field, organization.Get(field));
        }

        if (unknown.Count == 0)
        {
            Output.Bullet("None — this deployment matches what the SDK predicts.");
        }

        Output.Heading("Reading them");
        Output.Field("Has(...)", organization.Has("state_charity_registration_status"));
        Output.Field("GetString(...)", organization.GetString("state_charity_registration_status"));

        // A nested object a future version added is readable in whatever shape suits.
        var screening = organization.GetElement("watchlist_screening");

        if (screening is { ValueKind: JsonValueKind.Object })
        {
            Output.Field("watchlist_screening.provider", screening.Value.GetProperty("provider").GetString());
            Output.Field("watchlist_screening.matches", screening.Value.GetProperty("matches").GetRawText());
        }

        Output.Heading("An unknown member inside a known object");

        foreach (var entry in organization.OrganizationTypes)
        {
            Output.Field("deductibility_status_description", entry.DeductibilityStatusDescription);
            Output.Field("future_deductibility_note", entry.GetString("future_deductibility_note"));
        }

        Output.Heading("An enum value outside the documented set");
        Output.Field("foundation_type_code", organization.FoundationTypeCode);
        Output.Field("this application would", organization.FoundationTypeCode switch
        {
            "pc" => "route as a public charity",
            "pf" => "route as a private foundation",

            // Never a friendly default. An unrecognized classification is a reason to
            // ask a human, not to guess.
            _ => "route to review — the code is not one this application maps",
        });

        Output.Heading("The whole envelope, unmodified");
        Output.Field("Raw.IsJson", result.Raw.IsJson);
        Output.Field("Raw keys", string.Join(", ", result.Raw.Envelope.EnumerateObject().Select(p => p.Name)));

        Output.Note(
            "The model keeps the wire fields as its store and layers typed properties over\n"
            + "them, so a field the API adds tomorrow is readable today. Log the unknown\n"
            + "ones — they are how you find out the API moved.");
    }
}
