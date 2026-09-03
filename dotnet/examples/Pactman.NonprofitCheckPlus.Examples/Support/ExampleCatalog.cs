using System;
using System.Collections.Generic;
using System.Linq;
using System.Reflection;

namespace Pactman.NonprofitCheckPlus.Examples;

/// <summary>Every example in this assembly, discovered by reflection.</summary>
/// <remarks>
/// Discovery rather than a hand-kept list, so an example that is added but forgotten
/// cannot quietly stop being run by CI — the failure mode a registry has and a scan
/// does not.
/// </remarks>
public static class ExampleCatalog
{
    /// <summary>All examples, ordered by identifier.</summary>
    public static IReadOnlyList<IExample> All { get; } = typeof(ExampleCatalog).Assembly
        .GetTypes()
        .Where(type => typeof(IExample).IsAssignableFrom(type) && !type.IsAbstract && !type.IsInterface)
        .Select(type => (IExample)Activator.CreateInstance(type)!)
        .OrderBy(example => example.Id, StringComparer.Ordinal)
        .ToList();

    /// <summary>The examples whose identifier contains any of the given filters.</summary>
    /// <param name="filters">Substrings to match; empty matches everything.</param>
    /// <returns>The matching examples, in catalog order.</returns>
    public static IReadOnlyList<IExample> Matching(IReadOnlyList<string> filters) =>
        filters.Count == 0
            ? All
            : All.Where(example =>
                filters.Any(filter => example.Id.Contains(filter, StringComparison.OrdinalIgnoreCase)))
                .ToList();
}
