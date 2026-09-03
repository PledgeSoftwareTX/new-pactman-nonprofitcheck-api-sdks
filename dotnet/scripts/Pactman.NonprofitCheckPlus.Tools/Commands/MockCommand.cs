using System;
using System.Globalization;
using System.Threading;
using System.Threading.Tasks;
using Pactman.NonprofitCheckPlus.Dev;

namespace Pactman.NonprofitCheckPlus.Tools.Commands;

/// <summary>
/// Runs the bundled fixture API until interrupted.
/// </summary>
/// <remarks>
/// Point the SDK at it with <c>BaseUrl</c>, and use the key it prints.
/// </remarks>
internal static class MockCommand
{
    internal static async Task<int> RunAsync(string[] args)
    {
        var port = Option(args, "--port") is { } value
            ? int.Parse(value, CultureInfo.InvariantCulture)
            : 8787;

        var apiKey = Option(args, "--api-key");

        using var server = MockServer.Start(port, apiKey);

        Console.WriteLine($"Mock Pactman API listening on {server.BaseUrl}");
        Console.WriteLine($"Accepting Authorization: Bearer {server.ApiKey}");
        Console.WriteLine("Press Ctrl-C to stop.");

        using var stopped = new SemaphoreSlim(0, 1);

        Console.CancelKeyPress += (_, eventArgs) =>
        {
            // Handle the interrupt rather than letting it kill the process, so the
            // listener is closed and the port released on the way out.
            eventArgs.Cancel = true;
            stopped.Release();
        };

        await stopped.WaitAsync().ConfigureAwait(false);

        Console.WriteLine("\nStopped.");

        return 0;
    }

    /// <summary>Reads <c>--name value</c> or <c>--name=value</c>.</summary>
    private static string? Option(string[] args, string name)
    {
        for (var index = 0; index < args.Length; index++)
        {
            if (args[index] == name && index + 1 < args.Length)
            {
                return args[index + 1];
            }

            if (args[index].StartsWith(name + "=", StringComparison.Ordinal))
            {
                return args[index][(name.Length + 1)..];
            }
        }

        return null;
    }
}
