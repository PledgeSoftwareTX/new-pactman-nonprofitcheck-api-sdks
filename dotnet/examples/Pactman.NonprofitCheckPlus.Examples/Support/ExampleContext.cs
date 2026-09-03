using System;
using System.Net.Http;
using Pactman.NonprofitCheckPlus.Configuration;
using Pactman.NonprofitCheckPlus.Dev;

namespace Pactman.NonprofitCheckPlus.Examples;

/// <summary>
/// Wiring shared by every example: where to send requests, and where the key comes from.
/// </summary>
/// <remarks>
/// Examples that need an ordinary lookup use <see cref="Live"/> and run against
/// production, or against <c>PACTMAN_BASE_URL</c> when it is set. Examples that need a
/// record or a response a live API will not produce on request — a revoked exemption, an
/// OFAC match, an HTTP 429, a field newer than this SDK — use <see cref="WithFixtures"/>,
/// which starts the bundled fixture API and shuts it down on the way out.
/// </remarks>
public sealed class ExampleContext : IDisposable
{
    private readonly MockServer? _server;

    private ExampleContext(PactmanClient client, MockServer? server = null)
    {
        Client = client;
        _server = server;
    }

    /// <summary>The client this example sends through.</summary>
    public PactmanClient Client { get; }

    /// <summary>True when this example is running against the bundled fixture API.</summary>
    public bool UsesFixtures => _server is not null;

    /// <summary>A client pointed at production, or at <c>PACTMAN_BASE_URL</c> when set.</summary>
    /// <param name="timeout">Per-attempt timeout, when the default is not what the example shows.</param>
    /// <param name="retry">Retry policy, when the default is not what the example shows.</param>
    /// <returns>A context to dispose when the example finishes.</returns>
    public static ExampleContext Live(TimeSpan? timeout = null, RetryOptions? retry = null) =>
        new(new PactmanClient(new PactmanClientOptions
        {
            ApiKey = RequireApiKey(),
            BaseUrl = BaseUrlOverride(),
            Timeout = timeout,
            Retry = retry,
        }));

    /// <summary>
    /// A client pointed at the bundled fixture API.
    /// </summary>
    /// <remarks>
    /// <c>PACTMAN_BASE_URL</c> still wins, so the same example can be aimed at a different
    /// mock or a sandbox you have been given — and so the CI smoke runner can point every
    /// example at one shared server instead of thirty.
    /// </remarks>
    /// <param name="timeout">Per-attempt timeout, when the default is not what the example shows.</param>
    /// <param name="retry">Retry policy, when the default is not what the example shows.</param>
    /// <returns>A context to dispose when the example finishes.</returns>
    public static ExampleContext WithFixtures(TimeSpan? timeout = null, RetryOptions? retry = null)
    {
        var override_ = BaseUrlOverride();

        if (override_ is not null)
        {
            return new ExampleContext(new PactmanClient(new PactmanClientOptions
            {
                ApiKey = RequireApiKey(),
                BaseUrl = override_,
                Timeout = timeout,
                Retry = retry,
            }));
        }

        var server = MockServer.Start();

        return new ExampleContext(
            new PactmanClient(new PactmanClientOptions
            {
                ApiKey = server.ApiKey,
                BaseUrl = server.BaseUrl,
                Timeout = timeout,
                Retry = retry,
            }),
            server);
    }

    /// <summary>Builds a second client against the same target, for examples that need two.</summary>
    /// <param name="timeout">Per-attempt timeout for the sibling.</param>
    /// <param name="retry">Retry policy for the sibling.</param>
    /// <param name="maxRequestsPerSecond">A client-side ceiling, for the throttle example.</param>
    /// <returns>A client the caller owns and disposes.</returns>
    public PactmanClient Sibling(
        TimeSpan? timeout = null,
        RetryOptions? retry = null,
        double? maxRequestsPerSecond = null) =>
        new(new PactmanClientOptions
        {
            ApiKey = _server is null ? RequireApiKey() : _server.ApiKey,
            BaseUrl = Client.BaseUrl,
            Timeout = timeout,
            Retry = retry,
            MaxRequestsPerSecond = maxRequestsPerSecond,
        });

    /// <summary>The argument at a position, or a fallback. Examples take an EIN this way.</summary>
    /// <param name="args">The arguments the runner was given.</param>
    /// <param name="position">Which argument to read, counting from zero.</param>
    /// <param name="fallback">What to use when the argument was not supplied.</param>
    /// <returns>The argument, or the fallback.</returns>
    public static string Argument(string[] args, int position = 0, string fallback = "") =>
        args.Length > position && args[position].Length > 0 ? args[position] : fallback;

    /// <inheritdoc />
    public void Dispose()
    {
        Client.Dispose();
        _server?.Dispose();
    }

    private static string RequireApiKey()
    {
        var apiKey = DevEnv.Get(DevEnv.ApiKeyVariable);

        if (apiKey is null)
        {
            throw new ExampleFailedException(
                "Set PACTMAN_API_KEY before running this example. Load it from your secret "
                + "manager, or from a .env file excluded from git.");
        }

        return apiKey;
    }

    private static string? BaseUrlOverride() => DevEnv.Get("PACTMAN_BASE_URL");
}
