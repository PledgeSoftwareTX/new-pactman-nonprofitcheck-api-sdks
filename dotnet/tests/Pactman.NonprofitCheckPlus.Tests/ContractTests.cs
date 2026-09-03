using System;
using System.Collections.Generic;
using System.Linq;
using System.Text.Json;
using Pactman.NonprofitCheckPlus.Dev;
using Xunit;

namespace Pactman.NonprofitCheckPlus.Tests;

/// <summary>
/// The response-signature engine the smoke and baseline tools share.
/// </summary>
/// <remarks>
/// This is the part of the tooling with real logic in it, and the part whose mistakes are
/// silent: a diff engine that under-reports passes a green run over a broken API, and one
/// that over-reports gets switched off.
/// </remarks>
public class ContractTests
{
    private static SortedDictionary<string, string> Signature(string json) =>
        Contract.SignatureOf(JsonSerializer.Deserialize<JsonElement>(json));

    private static SortedDictionary<string, string> Map(params (string Path, string Token)[] entries)
    {
        var map = new SortedDictionary<string, string>(StringComparer.Ordinal);

        foreach (var (path, token) in entries)
        {
            map[path] = token;
        }

        return map;
    }

    [Theory]
    [InlineData("411787097", "digits:9")]
    [InlineData("01085-2643", "digits:5-4")]
    [InlineData("00", "digits:2")]
    [InlineData("3/25/2026 3:28:54 PM", "date")]
    [InlineData("2026-08-24T09:47:53Z", "date:iso")]
    [InlineData("https://pactman.org/profile", "url")]
    [InlineData("", "empty")]
    [InlineData("   ", "empty")]
    [InlineData("EXAMPLE NONPROFIT", "text")]
    public void ClassifiesAStringByItsForm(string value, string expected) =>
        Assert.Equal(expected, Contract.FormatOf(value));

    [Fact]
    public void BothOfacWordingsShareOneToken()
    {
        Assert.Equal("ofac-sentence", Contract.FormatOf(Fixtures.OfacNoMatch));
        Assert.Equal("ofac-sentence", Contract.FormatOf(Fixtures.OfacPossibleMatch));
    }

    [Fact]
    public void AGenuineWordingChangeFallsBackToText() =>
        Assert.Equal("text", Contract.FormatOf("This organization is not on any watchlist we checked."));

    [Fact]
    public void FlattensAResponseIntoPathsAndTokens()
    {
        var signature = Signature("""
            {"code":200,"data":{"ein":"411787097","pub78_verified":true,"revocation_code":null}}
            """);

        Assert.Equal("number", signature["code"]);
        Assert.Equal("object", signature["data"]);
        Assert.Equal("digits:9", signature["data.ein"]);
        Assert.Equal("boolean", signature["data.pub78_verified"]);
        Assert.Equal("null", signature["data.revocation_code"]);
    }

    [Fact]
    public void EveryElementOfAListContributesToOnePath()
    {
        var signature = Signature("""{"data":[{"ein":"411787097"},{"ein":"042103594"}]}""");

        Assert.Equal("array", signature["data"]);
        Assert.Equal("object", signature["data[]"]);
        Assert.Equal("digits:9", signature["data[].ein"]);

        // Two organizations describe one record shape, not two.
        Assert.Equal(3, signature.Count);
    }

    [Fact]
    public void APathCarryingTwoFormsRecordsBothSorted()
    {
        var signature = Signature("""{"data":[{"city":"WESTFIELD"},{"city":null}]}""");

        Assert.Equal("null|text", signature["data.city".Replace("data.", "data[].", StringComparison.Ordinal)]);
    }

    [Fact]
    public void NoValueFromTheResponseIsEverRecorded()
    {
        var signature = Signature("""{"data":{"organization_name":"SECRET NONPROFIT","ein":"411787097"}}""");

        Assert.DoesNotContain("SECRET NONPROFIT", string.Join("|", signature.Values), StringComparison.Ordinal);
        Assert.DoesNotContain("411787097", string.Join("|", signature.Values), StringComparison.Ordinal);
    }

    [Fact]
    public void SchemaDiffReportsAppearanceAndDisappearance()
    {
        var before = Map(("a", "text"), ("b", "number"));
        var after = Map(("a", "text"), ("c", "boolean"));

        var changes = Contract.SchemaDiff(before, after);

        // Removals first: a field that disappeared breaks callers that read it.
        Assert.Equal("removed", changes[0].Kind);
        Assert.Equal("b", changes[0].Path);
        Assert.Equal("added", changes[1].Kind);
        Assert.Equal("c", changes[1].Path);
    }

    [Fact]
    public void TypeDiffOnlyLooksAtPathsBothSidesHave()
    {
        var before = Map(("a", "digits:9"), ("b", "number"));
        var after = Map(("a", "text"), ("c", "boolean"));

        var changes = Contract.TypeDiff(before, after);

        var change = Assert.Single(changes);
        Assert.Equal("a", change.Path);
        Assert.Equal("digits:9", change.From);
        Assert.Equal("text", change.To);
    }

    [Theory]
    [InlineData("digits:9|null", "digits:9", true)]
    [InlineData("digits:9|null", "null", true)]
    [InlineData("digits:9|null", "text", false)]
    [InlineData("boolean|null", "boolean", true)]
    [InlineData("null|string", "text", true)]
    [InlineData("null|string", "digits:9", true)]
    [InlineData("null|string", "date", true)]
    [InlineData("null|string", "boolean", false)]
    [InlineData("null|string", "number", false)]
    public void StringIsAWildcardOverEveryStringForm(string declared, string token, bool permitted) =>
        Assert.Equal(permitted, Contract.Permits(declared, token));

    [Fact]
    public void SatisfiesRequiresEveryObservedFormToBeAllowed()
    {
        Assert.True(Contract.Satisfies("digits:9|null", "digits:9|null"));
        Assert.False(Contract.Satisfies("digits:9|null", "digits:9|text"));
    }

    [Fact]
    public void ARecordingExcusesNullabilityButNotAFormChange()
    {
        var before = Map(("data.pub78_city", "text"), ("data.ein", "digits:9"));
        var after = Map(("data.pub78_city", "null"), ("data.ein", "text"));

        var comparison = Contract.BaselineDiff(before, after);

        // pub78_city going null is this organization having no Pub 78 city, not the API
        // moving. ein turning into free text is the API moving.
        Assert.Equal(1, comparison.Nullable);

        var change = Assert.Single(comparison.Changes);
        Assert.Equal("data.ein", change.Path);
    }

    [Fact]
    public void ARecordingExcusesPathsUnderANullParent()
    {
        var before = Map(
            ("data.organization_types", "array"),
            ("data.organization_types[]", "object"),
            ("data.organization_types[].organization_type", "text"));

        var after = Map(("data.organization_types", "null"));

        var comparison = Contract.BaselineDiff(before, after);

        // The parent already accounts for the children's absence.
        Assert.DoesNotContain(comparison.Changes, change => change.Kind == "removed");
        Assert.Equal(2, comparison.Unreachable);
    }

    [Fact]
    public void ARecordingReportsAFieldThatGenuinelyDisappeared()
    {
        var before = Map(("data.ein", "digits:9"), ("data.address_line2", "text"));
        var after = Map(("data.ein", "digits:9"));

        var comparison = Contract.BaselineDiff(before, after);

        var change = Assert.Single(comparison.Changes);
        Assert.Equal("removed", change.Kind);
        Assert.Equal("data.address_line2", change.Path);
    }

    [Fact]
    public void ARecordingReportsAFieldTheApiStartedSending()
    {
        var before = Map(("data.ein", "digits:9"));
        var after = Map(("data.ein", "digits:9"), ("data.new_field", "text"));

        var comparison = Contract.BaselineDiff(before, after);

        var change = Assert.Single(comparison.Changes);
        Assert.Equal("added", change.Kind);
        Assert.Equal("data.new_field", change.Path);
    }

    [Fact]
    public void CoverageReportsAVanishedContainerOnceAtItsShallowestPath()
    {
        var expected = Map(
            ("data", "object"),
            ("data.ein", "digits:9"),
            ("data.city", "text"),
            ("data.state", "text"));

        var observed = Map(("code", "number"));

        var comparison = Contract.CoverageDiff(expected, observed);

        // A data that stopped arriving is one failure, not four.
        var removed = comparison.Changes.Where(change => change.Kind == "removed").ToList();
        Assert.Equal("data", Assert.Single(removed).Path);
    }

    [Fact]
    public void CoverageExcusesChildrenOfANullParentAndCountsThem()
    {
        var expected = Map(
            ("errors", "array|null"),
            ("errors[]", "object"),
            ("errors[].reason", "string"));

        var observed = Map(("errors", "null"));

        var comparison = Contract.CoverageDiff(expected, observed);

        // Every successful response has a null errors; reporting these would fail every
        // green run and say nothing.
        Assert.Empty(comparison.Changes);
        Assert.Equal(2, comparison.Unreachable);
    }

    [Fact]
    public void CoverageReportsAFieldTheApiInvented()
    {
        var expected = Map(("data.ein", "digits:9"));
        var observed = Map(("data.ein", "digits:9"), ("data.surprise", "text"));

        var change = Assert.Single(Contract.CoverageDiff(expected, observed).Changes);

        Assert.Equal("added", change.Kind);
        Assert.Equal("data.surprise", change.Path);
    }

    [Fact]
    public void ContractDiffNamesOnlyTheOffendingTokens()
    {
        var expected = Map(("data.pub78_verified", "boolean|null"));
        var observed = Map(("data.pub78_verified", "boolean|null|text"));

        var change = Assert.Single(Contract.ContractDiff(expected, observed));

        Assert.Equal("boolean|null", change.From);
        Assert.Equal("text", change.To);
    }

    [Fact]
    public void ContractDiffIgnoresPathsTheContractHasNeverHeardOf()
    {
        var expected = Map(("data.ein", "digits:9"));
        var observed = Map(("data.ein", "digits:9"), ("data.surprise", "text"));

        // A field the API invented is CoverageDiff's to report, so it is one failure
        // rather than two.
        Assert.Empty(Contract.ContractDiff(expected, observed));
    }

    [Fact]
    public void ComposesTheExpectedSignatureForBothEndpoints()
    {
        var contract = Fixtures.ResponseContract();

        var single = Contract.ComposeExpected(contract, "single");
        var bulk = Contract.ComposeExpected(contract, "bulk");

        Assert.Equal("null|object", single["data"]);
        Assert.Equal("array|null", bulk["data"]);
        Assert.Equal("object", bulk["data[]"]);

        // The record is described once and used for both, so single and bulk cannot
        // drift apart in the contract the way they can on the wire.
        Assert.Equal(single["data.ein"], bulk["data[].ein"]);

        // The API sends a null in the deductibility list for a row it cannot resolve.
        Assert.Equal("null|object", single["data.organization_types[]"]);

        Assert.True(single.ContainsKey("errors[].eins[]"));
        Assert.True(single.ContainsKey("nonprofit_check_count"));
    }

    [Fact]
    public void EveryFixtureRecordSatisfiesTheContract()
    {
        var expected = Contract.ComposeExpected(Fixtures.ResponseContract(), "single");

        foreach (var ein in Fixtures.KnownEins)
        {
            var envelope = JsonSerializer.Deserialize<JsonElement>($$"""
                {"code":200,"message":"OK","errors":null,"timeTaken":3,"nonprofit_check_count":1,
                 "data":{{Fixtures.Organization(ein).ToJsonString()}}}
                """);

            var offending = Contract.ContractDiff(expected, Contract.SignatureOf(envelope));

            Assert.True(
                offending.Count == 0,
                $"Fixture {ein} carries values the contract does not predict:\n"
                + Contract.FormatChanges(offending));
        }
    }

    [Fact]
    public void SummarizesOnlyTheCountsThatAreNotZero()
    {
        var changes = new[]
        {
            new Change("removed", "a"),
            new Change("removed", "b"),
            new Change("added", "c"),
        };

        Assert.Equal("2 removed, 1 added", Contract.SummarizeChanges(changes));
        Assert.Equal("no differences", Contract.SummarizeChanges(Array.Empty<Change>()));
    }
}
