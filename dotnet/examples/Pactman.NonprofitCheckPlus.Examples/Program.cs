using System;
using System.Linq;
using System.Threading.Tasks;
using Pactman.NonprofitCheckPlus.Dev;
using Pactman.NonprofitCheckPlus.Examples;

// Runs one example, or lists them all.
//
//   dotnet run --project examples/Pactman.NonprofitCheckPlus.Examples -- --list
//   dotnet run --project examples/Pactman.NonprofitCheckPlus.Examples -- ex-01
//   dotnet run --project examples/Pactman.NonprofitCheckPlus.Examples -- quickstart 41-1787097
//
// Every example reads PACTMAN_API_KEY from the environment or from the .env beside the
// package, and contains no credentials. To run all of them against the bundled fixture
// API, which is what CI does, use the tools project's examples-smoke command.

DevEnv.LoadEnvFile();

if (args.Length == 0 || args[0] is "--list" or "-l" or "--help" or "-h")
{
    Console.WriteLine("Examples for Pactman.NonprofitCheckPlus\n");

    foreach (var candidate in ExampleCatalog.All)
    {
        Console.WriteLine("  {0,-14} {1}", candidate.Id, candidate.Title);
    }

    Console.WriteLine("\nRun one with:  dotnet run --project examples/Pactman.NonprofitCheckPlus.Examples -- <id>");

    return 0;
}

var requested = args[0];
var example = ExampleCatalog.All.FirstOrDefault(
    candidate => string.Equals(candidate.Id, requested, StringComparison.OrdinalIgnoreCase));

if (example is null)
{
    Output.Error($"No example called \"{requested}\". Run with --list to see them all.");

    return 2;
}

try
{
    await example.RunAsync(args.Skip(1).ToArray());

    return 0;
}
catch (ExampleFailedException error)
{
    Output.Error(error.Message);

    return 1;
}
