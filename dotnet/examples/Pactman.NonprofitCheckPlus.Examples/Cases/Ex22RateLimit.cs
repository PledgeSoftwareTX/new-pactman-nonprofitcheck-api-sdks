using System;
using System.Diagnostics;
using System.Threading.Tasks;
using Pactman.NonprofitCheckPlus.Configuration;
using Pactman.NonprofitCheckPlus.Dev;
using Pactman.NonprofitCheckPlus.Exceptions;

namespace Pactman.NonprofitCheckPlus.Examples.Cases;

/// <summary>
/// EX-22 — Rate limits and <c>Retry-After</c>.
/// </summary>
/// <remarks>
/// A 429 with a server-supplied delay, honored automatically by the retry policy and
/// readable on the exception when the policy gives up.
/// </remarks>
public sealed class Ex22RateLimit : IExample
{
    /// <inheritdoc />
    public string Id => "ex-22";

    /// <inheritdoc />
    public string Title => "HTTP 429, Retry-After, and a client-side ceiling.";

    /// <inheritdoc />
    public async Task RunAsync(string[] args)
    {
        using var context = ExampleContext.WithFixtures();

        Output.Heading("A 429 the policy will not retry past");

        // Retrying is disabled so the exception surfaces rather than being absorbed —
        // this example is about what the error carries.
        using var noRetry = context.Sibling(retry: RetryOptions.None);

        try
        {
            await noRetry.Nonprofits.CheckAsync(Fixtures.ControlEins.RateLimited);

            throw new ExampleFailedException("Expected HTTP 429; the request succeeded.");
        }
        catch (PactmanRateLimitException error)
        {
            Output.Field("type", error.GetType().Name);
            Output.Field("category", error.Category.ToWireValue());
            Output.Field("status", error.Status);
            Output.Field("RetryAfter", error.RetryAfter);
            Output.Field("attempts", error.Attempts);
            Output.Field("requestId", error.RequestId);
            Output.Field("message", error.Message);
        }

        Output.Heading("The same call, with retrying on");

        // The default policy honors Retry-After before falling back to backoff, so a
        // server that asks for one second gets one second — not the computed delay.
        using var retrying = context.Sibling(retry: new RetryOptions { MaxRetries = 1 });

        var started = Stopwatch.StartNew();

        try
        {
            await retrying.Nonprofits.CheckAsync(Fixtures.ControlEins.RateLimited);
        }
        catch (PactmanRateLimitException error)
        {
            Output.Field("still 429 after", $"{error.Attempts} attempt(s)");
            Output.Field("elapsed", $"{started.Elapsed.TotalSeconds:F1}s — the server's Retry-After was waited out");
        }

        Output.Heading("Staying under the limit in the first place");

        // A courtesy throttle in front of the server's limit. Off by default: the
        // server's limits are authoritative and may change.
        using var throttled = context.Sibling(maxRequestsPerSecond: 2);

        var spaced = Stopwatch.StartNew();

        for (var index = 0; index < 3; index++)
        {
            await throttled.Nonprofits.CheckAsync(Fixtures.Eins.PublicCharity);
        }

        Output.Field("3 requests at 2/sec", $"{spaced.Elapsed.TotalSeconds:F1}s");

        Output.Note(
            "Honor Retry-After; never busy-loop a 429. A client-side ceiling is a courtesy,\n"
            + "not a substitute for handling the exception — the server's limit is the one\n"
            + "that counts and it can change without notice.");
    }
}
