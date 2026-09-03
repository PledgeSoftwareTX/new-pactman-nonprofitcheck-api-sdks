using System;

namespace Pactman.NonprofitCheckPlus.Dev;

/// <summary>One difference between two response signatures.</summary>
/// <param name="Kind"><c>removed</c>, <c>added</c> or <c>changed</c>.</param>
/// <param name="Path">The signature path the difference is at.</param>
/// <param name="Token">The token, for an addition or a removal.</param>
/// <param name="From">The token before, for a change.</param>
/// <param name="To">The token after, for a change.</param>
public sealed record Change(string Kind, string Path, string? Token = null, string? From = null, string? To = null)
{
    /// <summary>Removals first: a field that disappeared breaks callers that read it.</summary>
    internal int Rank => Kind switch
    {
        "removed" => 0,
        "changed" => 1,
        "added" => 2,
        _ => 3,
    };

    /// <inheritdoc />
    public override string ToString() => Kind switch
    {
        "removed" => $"- {Path} was {Token ?? "?"}",
        "added" => $"+ {Path} is {Token ?? "?"}",
        _ => $"~ {Path} {From ?? "?"} → {To ?? "?"}",
    };
}
