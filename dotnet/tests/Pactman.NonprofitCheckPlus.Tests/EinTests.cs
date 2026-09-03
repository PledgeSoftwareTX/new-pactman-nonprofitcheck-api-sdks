using System;
using System.Collections.Generic;
using Pactman.NonprofitCheckPlus.Exceptions;
using Xunit;

namespace Pactman.NonprofitCheckPlus.Tests;

public class EinTests
{
    [Theory]
    [InlineData("411787097", "411787097")]
    [InlineData("41-1787097", "411787097")]
    [InlineData("  41-1787097  ", "411787097")]
    [InlineData("042103594", "042103594")]
    public void NormalizesAcceptedShapes(string input, string expected)
    {
        Assert.Equal(expected, Ein.Normalize(input));
        Assert.True(Ein.IsValid(input));
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("   ")]
    [InlineData("4117870")]
    [InlineData("4117870977")]
    [InlineData("41-178-7097")]
    [InlineData("41178709X")]
    [InlineData("411-787097")]
    public void RejectsAnythingElse(string? input)
    {
        Assert.False(Ein.IsValid(input));
        Assert.Throws<PactmanValidationException>(() => Ein.Normalize(input));
    }

    [Fact]
    public void AnInvalidEinCarriesItsOwnIssue()
    {
        var error = Assert.Throws<PactmanValidationException>(() => Ein.Normalize("nope"));

        var issue = Assert.Single(error.Issues);
        Assert.Null(issue.Index);
        Assert.Equal("nope", issue.Value);
        Assert.Equal(ErrorCategory.Validation, error.Category);
        Assert.Equal(ErrorOrigin.Local, error.Origin);
    }

    [Fact]
    public void NormalizeManyKeepsOrderAndDuplicates()
    {
        var normalized = Ein.NormalizeMany(new[] { "41-1787097", "411787097", "04-2103594" });

        Assert.Equal(new[] { "411787097", "411787097", "042103594" }, normalized);
    }

    [Fact]
    public void NormalizeManyReportsEveryFailureAtOnce()
    {
        var error = Assert.Throws<PactmanValidationException>(
            () => Ein.NormalizeMany(new[] { "411787097", "bad", "411787097", "worse" }));

        Assert.Equal(2, error.Issues.Count);
        Assert.Equal(new int?[] { 1, 3 }, new[] { error.Issues[0].Index, error.Issues[1].Index });
        Assert.Contains("2 of 4 EINs are invalid (at index 1, 3)", error.Message, StringComparison.Ordinal);
        Assert.Contains("No request was sent", error.Message, StringComparison.Ordinal);
    }

    [Fact]
    public void NormalizeManyRefusesANullCollection()
    {
        Assert.Throws<PactmanValidationException>(() => Ein.NormalizeMany(null!));
    }

    [Fact]
    public void AnIndexAppearsInASingleItemMessage()
    {
        var error = Assert.Throws<PactmanValidationException>(() => Ein.Normalize("bad", 7));

        Assert.Contains("at index 7", error.Message, StringComparison.Ordinal);
        Assert.Equal(7, Assert.Single(error.Issues).Index);
    }
}
