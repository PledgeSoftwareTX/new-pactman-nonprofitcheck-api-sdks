using System.Text.Json;
using System.Threading.Tasks;
using Pactman.NonprofitCheckPlus.Dev;

namespace Pactman.NonprofitCheckPlus.Examples.Cases;

/// <summary>
/// EX-21 — Billing-cycle usage tracking.
/// </summary>
/// <remarks>
/// <c>nonprofit_check_count</c>, surfaced as <c>CheckCount</c>, is the running total of
/// checks consumed so far in the current billing cycle — never the size of the request
/// you just made. The test is one thing: fetch one nonprofit by EIN, and confirm the API
/// sent that counter as a JSON number. The SDK maps anything else to <c>null</c>, which
/// downstream is indistinguishable from "not reported", so the check reads the uncoerced
/// value off <c>Raw</c>.
/// </remarks>
public sealed class Ex21UsageTracking : IExample
{
    /// <inheritdoc />
    public string Id => "ex-21";

    /// <inheritdoc />
    public string Title => "nonprofit_check_count as a cycle total, verified to arrive as a number.";

    /// <inheritdoc />
    public async Task RunAsync(string[] args)
    {
        using var context = ExampleContext.Live();
        var ein = ExampleContext.Argument(args, 0, Fixtures.Eins.PublicCharity);

        var result = await context.Client.Nonprofits.CheckAsync(ein);

        // `CheckCount` is `int?`, and the SDK produces that `null` both for a counter the
        // API sent as null and for one it sent as `"42"`. Only `Raw`, which nothing has
        // coerced, tells them apart.
        var envelope = result.Raw.Envelope;
        JsonElement wireValue = default;
        var returned = envelope.ValueKind == JsonValueKind.Object
            && envelope.TryGetProperty("nonprofit_check_count", out wireValue);
        var wireType = returned ? JsonTypeOf(wireValue) : Output.NotReturned;

        Output.Heading("nonprofit_check_count on the wire");
        Output.Field("ein", ein);
        Output.Field("wire type", wireType);
        Output.Field("CheckCount", result.CheckCount);

        Output.Note(
            "The counter is cumulative for the billing cycle and resets when a new one starts.\n"
            + "A bulk call for five EINs does not return 5 — it returns your cycle total.");

        if (wireType != "number")
        {
            var detail = returned ? " " + wireValue.GetRawText() : string.Empty;

            throw new ExampleFailedException(
                $"nonprofit_check_count arrived as {wireType}{detail}, not a number, "
                + "so CheckCount reads null.");
        }
    }

    /// <summary>The JSON type of a value, in the vocabulary the response contract uses.</summary>
    /// <param name="value">The element to classify.</param>
    /// <returns>The contract's name for its type.</returns>
    private static string JsonTypeOf(JsonElement value) => value.ValueKind switch
    {
        JsonValueKind.Null => "null",
        JsonValueKind.True or JsonValueKind.False => "boolean",
        JsonValueKind.Number => "number",
        JsonValueKind.String => "string",
        JsonValueKind.Array => "array",
        JsonValueKind.Object => "object",
        _ => value.ValueKind.ToString().ToLowerInvariant(),
    };
}
