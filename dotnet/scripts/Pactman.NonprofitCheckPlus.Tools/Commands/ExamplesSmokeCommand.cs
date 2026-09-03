using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Threading.Tasks;
using Pactman.NonprofitCheckPlus.Dev;
using Pactman.NonprofitCheckPlus.Examples;

namespace Pactman.NonprofitCheckPlus.Tools.Commands;

/// <summary>
/// Runs every documented example against the bundled fixture API.
/// </summary>
/// <remarks>
/// This is what CI runs. An example that stops working is a documentation bug, and this
/// catches it on the push that caused it rather than in somebody's editor three weeks
/// later.
/// <para>
/// One server for the whole run, and every example inherits <c>PACTMAN_BASE_URL</c> — so
/// the ones that would otherwise start their own fixture API share this instance.
/// </para>
/// </remarks>
internal static class ExamplesSmokeCommand
{
    internal static async Task<int> RunAsync(string[] args)
    {
        var verbose = DevEnv.Get("EXAMPLES_VERBOSE") is not null || args.Contains("--verbose");
        var filters = args.Where(arg => !arg.StartsWith("--", StringComparison.Ordinal)).ToList();
        var examples = ExampleCatalog.Matching(filters);

        if (examples.Count == 0)
        {
            Console.Error.WriteLine("No examples matched.");

            return 1;
        }

        using var server = MockServer.Start();

        // Every example reads these, so all of them share one server and one billing
        // cycle rather than starting thirty listeners.
        Environment.SetEnvironmentVariable("PACTMAN_API_KEY", server.ApiKey);
        Environment.SetEnvironmentVariable("PACTMAN_BASE_URL", server.BaseUrl);

        Console.WriteLine($"Fixture API on {server.BaseUrl} — running {examples.Count} example(s)\n");

        var failures = new List<(string Name, string Detail)>();
        var started = Stopwatch.StartNew();
        var originalOut = Console.Out;

        foreach (var example in examples)
        {
            // Captured in-process. Examples are ordinary classes here rather than child
            // processes, so there is no pipe to deadlock on and no runtime to re-start
            // thirty times.
            var captured = new StringWriter();
            string? failure = null;

            Console.SetOut(captured);

            try
            {
                await example.RunAsync(Array.Empty<string>());
            }
            catch (Exception error)
            {
                failure = error is ExampleFailedException
                    ? error.Message
                    : error.ToString();
            }
            finally
            {
                Console.SetOut(originalOut);
            }

            if (failure is null)
            {
                Console.WriteLine($"  {Output.Mark("pass")} {example.Id}");
            }
            else
            {
                Console.WriteLine($"  {Output.Mark("fail")} {example.Id}");
                failures.Add((example.Id, failure));
            }

            if (verbose)
            {
                Console.Write(captured.ToString());
            }
        }

        Console.WriteLine(
            $"\n{examples.Count - failures.Count} passed, {failures.Count} failed "
            + $"in {started.Elapsed.TotalSeconds:F1}s");

        foreach (var (name, detail) in failures)
        {
            Console.WriteLine($"\n{Output.Paint(31, name)}\n{detail}");
        }

        return failures.Count == 0 ? 0 : 1;
    }
}
