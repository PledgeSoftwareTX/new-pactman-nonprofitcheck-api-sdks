using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.Json;
using Pactman.NonprofitCheckPlus.Dev;

namespace Pactman.NonprofitCheckPlus.Tools.Commands;

/// <summary>
/// Prints the signature of a JSON response: which fields exist, and what form each value
/// takes. No value from the response is ever printed.
/// </summary>
/// <remarks>
/// Use it to record a baseline by hand, or to see what shape a payload actually has.
/// Given two files it diffs them instead.
/// </remarks>
internal static class ContractCommand
{
    internal static int Run(string[] args)
    {
        var sources = args.Length == 0 ? new[] { "-" } : args;

        if (sources.Length == 1)
        {
            var signature = SignatureFrom(sources[0]);

            Console.WriteLine(JsonSerializer.Serialize(
                signature,
                new JsonSerializerOptions { WriteIndented = true }));

            return 0;
        }

        var baseline = SignatureFrom(sources[0]);
        var current = SignatureFrom(sources[1]);

        var schema = Contract.SchemaDiff(baseline, current);
        var types = Contract.TypeDiff(baseline, current);

        Console.WriteLine(
            $"{schema.Count} field(s) appeared or disappeared, {types.Count} changed shape\n");

        foreach (var change in schema.Concat(types))
        {
            Console.WriteLine("  " + change);
        }

        // A field that disappeared or changed shape breaks callers. An addition does not.
        var breaking = schema.Any(change => change.Kind == "removed");

        return breaking || types.Count > 0 ? 1 : 0;
    }

    private static SortedDictionary<string, string> SignatureFrom(string source)
    {
        var raw = source == "-" ? Console.In.ReadToEnd() : File.ReadAllText(source);

        if (string.IsNullOrWhiteSpace(raw))
        {
            Console.Error.WriteLine($"Nothing to read from {source}.");
            Environment.Exit(1);
        }

        JsonElement decoded;

        try
        {
            decoded = JsonSerializer.Deserialize<JsonElement>(raw);
        }
        catch (JsonException error)
        {
            Console.Error.WriteLine($"{source} is not valid JSON: {error.Message}");
            Environment.Exit(1);

            throw;
        }

        // Already a signature? Then it is a flat map of path to token; pass it through.
        if (decoded.ValueKind == JsonValueKind.Object
            && decoded.EnumerateObject().Any()
            && decoded.EnumerateObject().All(property => property.Value.ValueKind == JsonValueKind.String))
        {
            var passthrough = new SortedDictionary<string, string>(StringComparer.Ordinal);

            foreach (var property in decoded.EnumerateObject())
            {
                passthrough[property.Name] = property.Value.GetString()!;
            }

            return passthrough;
        }

        return Contract.SignatureOf(decoded);
    }
}
