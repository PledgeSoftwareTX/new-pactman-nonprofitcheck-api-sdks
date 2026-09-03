using System;
using System.Linq;
using System.Threading.Tasks;
using Pactman.NonprofitCheckPlus.Dev;
using Pactman.NonprofitCheckPlus.Tools.Commands;

// The development commands for this SDK.
//
//   dotnet run --project scripts/Pactman.NonprofitCheckPlus.Tools -- mock [--port 8787]
//   dotnet run --project scripts/Pactman.NonprofitCheckPlus.Tools -- examples-smoke [ex-22 ex-23]
//   dotnet run --project scripts/Pactman.NonprofitCheckPlus.Tools -- smoke-live [ein ...]
//   dotnet run --project scripts/Pactman.NonprofitCheckPlus.Tools -- baseline-record [--dry-run]
//   dotnet run --project scripts/Pactman.NonprofitCheckPlus.Tools -- contract [file ...]

DevEnv.LoadEnvFile();

var command = args.Length > 0 ? args[0] : "--help";
var rest = args.Skip(1).ToArray();

return command switch
{
    "mock" => await MockCommand.RunAsync(rest),
    "examples-smoke" => await ExamplesSmokeCommand.RunAsync(rest),
    "smoke-live" => await SmokeLiveCommand.RunAsync(rest),
    "baseline-record" => await BaselineRecordCommand.RunAsync(rest),
    "contract" => ContractCommand.Run(rest),
    _ => Usage(command),
};

static int Usage(string command)
{
    var unknown = command is not ("--help" or "-h");

    if (unknown)
    {
        Console.Error.WriteLine($"Unknown command \"{command}\".\n");
    }

    Console.WriteLine("""
        Pactman.NonprofitCheckPlus development commands

          mock [--port N] [--api-key K]   Serve the bundled fixture API until interrupted.
          examples-smoke [filter ...]     Run every documented example against the fixture API.
          smoke-live [ein ...]            Check a live deployment against the contract and baseline.
          baseline-record [--dry-run]     Re-record the production baseline. Spends billable checks.
          contract [file ...]             Print a response signature, or diff two of them.

        The key and any target override come from the environment or the .env beside
        the package. Nothing here ever prints a value from a response.
        """);

    return unknown ? 2 : 0;
}
