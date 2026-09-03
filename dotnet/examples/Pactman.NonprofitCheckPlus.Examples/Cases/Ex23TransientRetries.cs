using System;
using System.Threading.Tasks;
using Pactman.NonprofitCheckPlus.Configuration;
using Pactman.NonprofitCheckPlus.Dev;
using Pactman.NonprofitCheckPlus.Exceptions;

namespace Pactman.NonprofitCheckPlus.Examples.Cases;

/// <summary>
/// EX-23 — Transient failures and retries.
/// </summary>
/// <remarks>
/// An endpoint that fails twice and then succeeds, and the statuses that are never retried
/// however the policy is configured.
/// </remarks>
public sealed class Ex23TransientRetries : IExample
{
    /// <inheritdoc />
    public string Id => "ex-23";

    /// <inheritdoc />
    public string Title => "Retrying a transient 503, and the statuses that are never retried.";

    /// <inheritdoc />
    public async Task RunAsync(string[] args)
    {
        using var context = ExampleContext.WithFixtures();

        Output.Heading("The default policy");
        Output.Field("MaxRetries", RetryOptions.Default.MaxRetries);
        Output.Field("InitialDelay", RetryOptions.Default.InitialDelay);
        Output.Field("MaxDelay", RetryOptions.Default.MaxDelay);
        Output.Field("BackoffFactor", RetryOptions.Default.BackoffFactor);
        Output.Field("Jitter", RetryOptions.Default.Jitter);
        Output.Field("RetryableStatuses", string.Join(", ", RetryOptions.Default.RetryableStatuses));
        Output.Field("RespectRetryAfter", RetryOptions.Default.RespectRetryAfter);

        Output.Heading("A 503 that clears");

        // The fixture answers 503 twice and then succeeds, which is exactly the shape a
        // retry policy exists for.
        var result = await context.Client.Nonprofits.CheckAsync(Fixtures.ControlEins.TransientFailure);

        Output.Field("status", result.Status);
        Output.Field("organization", result.Nonprofit?.OrganizationName);
        Output.Field("the caller saw", "one successful call — the failures were absorbed");

        Output.Heading("The same call with retrying off");

        using var noRetry = context.Sibling(retry: RetryOptions.None);

        try
        {
            await noRetry.Nonprofits.CheckAsync(Fixtures.ControlEins.TransientFailure);
            Output.Field("result", "succeeded — the fixture's failure budget had reset");
        }
        catch (PactmanServerException error)
        {
            Output.Field("type", error.GetType().Name);
            Output.Field("status", error.Status);
            Output.Field("attempts", error.Attempts);
        }

        Output.Heading("Statuses that are never retried");

        // 400, 401, 403 and 404 will not become a different answer, so the SDK refuses
        // to retry them however the policy is written.
        using var stubborn = context.Sibling(
            retry: new RetryOptions { MaxRetries = 5, RetryableStatuses = new[] { 404, 500, 503 } });

        try
        {
            await stubborn.Nonprofits.CheckAsync(Fixtures.Eins.NoRecord);
            Output.Field("404", "returned as an empty result rather than an error");
        }
        catch (PactmanNotFoundException error)
        {
            Output.Field("404 listed as retryable", "still not retried");
            Output.Field("attempts", error.Attempts);
        }

        Output.Heading("Tuning for one request");
        Output.Bullet("client.Retry with { MaxRetries = 5 } — start from the policy in force.");
        Output.Bullet("RetryOptions.None — no retrying for this request.");
        Output.Bullet("A CancellationToken bounds the whole call, retries included.");

        Output.Note(
            "Full jitter randomizes each delay across the whole range, so clients that\n"
            + "failed together do not retry in lockstep and re-create the outage.");
    }
}
