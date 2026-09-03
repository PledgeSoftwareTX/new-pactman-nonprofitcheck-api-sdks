using System;
using System.Diagnostics;
using System.Threading;
using System.Threading.Tasks;
using Pactman.NonprofitCheckPlus.Configuration;
using Pactman.NonprofitCheckPlus.Dev;
using Pactman.NonprofitCheckPlus.Exceptions;

namespace Pactman.NonprofitCheckPlus.Examples.Cases;

/// <summary>
/// EX-24 — Timeouts and operation budgets.
/// </summary>
/// <remarks>
/// A per-attempt deadline is not a budget for the whole call. A cancellation token is,
/// and the two failures stay distinguishable.
/// </remarks>
public sealed class Ex24TimeoutsAndBudgets : IExample
{
    /// <inheritdoc />
    public string Id => "ex-24";

    /// <inheritdoc />
    public string Title => "Per-attempt timeouts versus a budget for the whole call.";

    /// <inheritdoc />
    public async Task RunAsync(string[] args)
    {
        using var context = ExampleContext.WithFixtures();

        Output.Heading("A per-attempt deadline");

        using var impatient = context.Sibling(timeout: TimeSpan.FromMilliseconds(300), retry: RetryOptions.None);

        try
        {
            await impatient.Nonprofits.CheckAsync(Fixtures.ControlEins.Slow);

            throw new ExampleFailedException("Expected a timeout; the slow endpoint answered in time.");
        }
        catch (PactmanTimeoutException error)
        {
            Output.Field("type", error.GetType().Name);
            Output.Field("category", error.Category.ToWireValue());
            Output.Field("origin", error.Origin.ToWireValue());
            Output.Field("Timeout", error.Timeout);
            Output.Field("attempts", error.Attempts);
        }

        Output.Heading("Why the deadline is not a budget");

        // Each attempt gets the full deadline, so a policy with two retries can take
        // three times as long as the number you configured.
        var policy = new RetryOptions { MaxRetries = 2, InitialDelay = TimeSpan.FromMilliseconds(50) };

        Output.Field("Timeout", "300ms per attempt");
        Output.Field("MaxRetries", policy.MaxRetries);
        Output.Field("worst case", "3 attempts x 300ms, plus backoff between them");

        using var retrying = context.Sibling(timeout: TimeSpan.FromMilliseconds(300), retry: policy);

        var started = Stopwatch.StartNew();

        try
        {
            await retrying.Nonprofits.CheckAsync(Fixtures.ControlEins.Slow);
        }
        catch (PactmanTimeoutException error)
        {
            Output.Field("elapsed", $"{started.Elapsed.TotalMilliseconds:F0}ms over {error.Attempts} attempts");
        }

        Output.Heading("A budget for the whole call");

        // This is the one that bounds the operation. It covers every attempt and every
        // backoff between them.
        using var budget = new CancellationTokenSource(TimeSpan.FromMilliseconds(400));
        var bounded = Stopwatch.StartNew();

        try
        {
            await retrying.Nonprofits.CheckAsync(Fixtures.ControlEins.Slow, cancellationToken: budget.Token);
        }
        catch (OperationCanceledException)
        {
            Output.Field("type", "OperationCanceledException");
            Output.Field("elapsed", $"{bounded.Elapsed.TotalMilliseconds:F0}ms");

            // The distinction is deliberate: "I gave up" never arrives dressed as "the
            // API was too slow", so a caller can tell its own deadline from the API's.
            Output.Field("not a", nameof(PactmanTimeoutException));
        }

        Output.Note(
            "Set Timeout for one attempt and a CancellationToken for the operation. In a\n"
            + "request handler, pass the framework's own cancellation token straight\n"
            + "through — when the client hangs up, the outbound call stops too.");
    }
}
