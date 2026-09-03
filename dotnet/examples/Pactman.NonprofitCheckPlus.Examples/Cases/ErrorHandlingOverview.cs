using System;
using System.Threading.Tasks;
using Pactman.NonprofitCheckPlus.Configuration;
using Pactman.NonprofitCheckPlus.Dev;
using Pactman.NonprofitCheckPlus.Exceptions;

namespace Pactman.NonprofitCheckPlus.Examples.Cases;

/// <summary>The error taxonomy in one file: what to catch, and what each type carries.</summary>
public sealed class ErrorHandlingOverview : IExample
{
    /// <inheritdoc />
    public string Id => "error-handling";

    /// <inheritdoc />
    public string Title => "The error taxonomy: what to catch and what each type carries.";

    /// <inheritdoc />
    public async Task RunAsync(string[] args)
    {
        using var context = ExampleContext.WithFixtures();
        using var client = context.Sibling(retry: RetryOptions.None, timeout: TimeSpan.FromMilliseconds(300));

        Output.Heading("Local validation — nothing is sent");

        await Show(() => client.Nonprofits.CheckAsync("not-an-ein"));

        Output.Heading("Rate limited");

        await Show(() => client.Nonprofits.CheckAsync(Fixtures.ControlEins.RateLimited));

        Output.Heading("Server error");

        await Show(() => client.Nonprofits.CheckAsync(Fixtures.ControlEins.TransientFailure));

        Output.Heading("Timeout");

        await Show(() => client.Nonprofits.CheckAsync(Fixtures.ControlEins.Slow));

        Output.Heading("Not found");

        await Show(() => client.Nonprofits.CheckAsync(Fixtures.Eins.NoRecord));

        Output.Note(
            "Catch PactmanException to catch everything. Branch on the exception type or on\n"
            + "Category — never on message text, which is prose and will change.");
    }

    private static async Task Show(Func<Task> call)
    {
        try
        {
            await call();

            Output.Field("outcome", "succeeded");
        }
        catch (PactmanApiException error)
        {
            Output.Field("type", error.GetType().Name);
            Output.Field("category", error.Category.ToWireValue());
            Output.Field("origin", error.Origin.ToWireValue());
            Output.Field("status", error.Status);
            Output.Field("retryAfter", error.RetryAfter);
            Output.Field("requestId", error.RequestId);
            Output.Field("attempts", error.Attempts);
            Output.Field("message", error.Message);
        }
        catch (PactmanException error)
        {
            // Configuration, validation, timeout and network all land here: local
            // failures, with no HTTP response behind them.
            Output.Field("type", error.GetType().Name);
            Output.Field("category", error.Category.ToWireValue());
            Output.Field("origin", error.Origin.ToWireValue());
            Output.Field("message", error.Message);
        }
    }
}
