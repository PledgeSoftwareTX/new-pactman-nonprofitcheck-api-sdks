using System;
using System.Collections.Generic;
using System.Linq;
using System.Text.Json.Nodes;
using System.Threading.Tasks;
using Pactman.NonprofitCheckPlus.Configuration;
using Pactman.NonprofitCheckPlus.Exceptions;
using Pactman.NonprofitCheckPlus.Tests.Support;
using Xunit;

namespace Pactman.NonprofitCheckPlus.Tests;

public class BulkTests
{
    [Fact]
    public async Task PostsNormalizedEinsToThePublishedPath()
    {
        var handler = FakeHandler.Always(
            Stub.Json(Fixtures.Envelope(Fixtures.Organizations(Fixtures.Nonprofit()))));
        using var client = Fixtures.Client(handler);

        await client.Nonprofits.CheckBulkAsync(new[] { "41-1787097", "042103594" });

        var request = handler.LastRequest;

        Assert.Equal("POST", request.Method);
        Assert.Equal("/api/entities/nonprofitcheckbulk/v1/us/eins", request.Path);
        Assert.Equal("application/json; charset=utf-8", request.Header("Content-Type"));
        Assert.Equal(new[] { "411787097", "042103594" }, request.StringListBody());
    }

    [Fact]
    public async Task DuplicatesAreSentAsSuppliedByDefault()
    {
        var handler = FakeHandler.Always(Stub.Json(Fixtures.Envelope(new JsonArray())));
        using var client = Fixtures.Client(handler);

        await client.Nonprofits.CheckBulkAsync(new[] { "411787097", "411787097" });

        Assert.Equal(new[] { "411787097", "411787097" }, handler.LastRequest.StringListBody());
    }

    [Fact]
    public async Task DedupeRemovesDuplicatesKeepingFirstSeenOrder()
    {
        var handler = FakeHandler.Always(Stub.Json(Fixtures.Envelope(new JsonArray())));
        using var client = Fixtures.Client(handler);

        await client.Nonprofits.CheckBulkAsync(
            new[] { "41-1787097", "042103594", "411787097" },
            new BulkRequestOptions { Dedupe = true });

        Assert.Equal(new[] { "411787097", "042103594" }, handler.LastRequest.StringListBody());
    }

    [Fact]
    public async Task AnEmptyBatchNeverReachesTheNetwork()
    {
        var handler = FakeHandler.Always(Stub.Json(Fixtures.Envelope(new JsonArray())));
        using var client = Fixtures.Client(handler);

        await Assert.ThrowsAsync<PactmanValidationException>(
            () => client.Nonprofits.CheckBulkAsync(Array.Empty<string>()));

        Assert.Equal(0, handler.RequestCount);
    }

    [Fact]
    public async Task ABatchOverTheLimitNeverReachesTheNetwork()
    {
        var handler = FakeHandler.Always(Stub.Json(Fixtures.Envelope(new JsonArray())));
        using var client = Fixtures.Client(handler);

        var eins = Enumerable.Range(0, Endpoints.MaxBulkEins + 1)
            .Select(index => index.ToString("000000000", System.Globalization.CultureInfo.InvariantCulture))
            .ToArray();

        var error = await Assert.ThrowsAsync<PactmanValidationException>(
            () => client.Nonprofits.CheckBulkAsync(eins));

        Assert.Contains("at most 50 EINs", error.Message, StringComparison.Ordinal);
        Assert.Contains("does not chunk automatically", error.Message, StringComparison.Ordinal);
        Assert.Equal(0, handler.RequestCount);
    }

    [Fact]
    public async Task DedupeIsAppliedBeforeTheLimitIsChecked()
    {
        var handler = FakeHandler.Always(Stub.Json(Fixtures.Envelope(new JsonArray())));
        using var client = Fixtures.Client(handler);

        var eins = Enumerable.Repeat("411787097", Endpoints.MaxBulkEins + 10).ToArray();

        await client.Nonprofits.CheckBulkAsync(eins, new BulkRequestOptions { Dedupe = true });

        Assert.Single(handler.LastRequest.StringListBody());
    }

    [Fact]
    public async Task AMalformedEinIdentifiesItsIndexAndSendsNothing()
    {
        var handler = FakeHandler.Always(Stub.Json(Fixtures.Envelope(new JsonArray())));
        using var client = Fixtures.Client(handler);

        var error = await Assert.ThrowsAsync<PactmanValidationException>(
            () => client.Nonprofits.CheckBulkAsync(new[] { "411787097", "nope" }));

        Assert.Equal(1, Assert.Single(error.Issues).Index);
        Assert.Equal(0, handler.RequestCount);
    }

    [Fact]
    public async Task ReadsTheMatchedOrganizations()
    {
        var second = Fixtures.Nonprofit(organization =>
        {
            organization["ein"] = "042103594";
            organization["organization_name"] = "SECOND NONPROFIT";
        });

        var handler = FakeHandler.Always(Stub.Json(
            Fixtures.Envelope(Fixtures.Organizations(Fixtures.Nonprofit(), second))));
        using var client = Fixtures.Client(handler);

        var result = await client.Nonprofits.CheckBulkAsync(new[] { "411787097", "042103594" });

        Assert.Equal(2, result.Organizations.Count);
        Assert.Equal(new[] { "411787097", "042103594" }, result.Organizations.Select(o => o.Ein));
    }

    [Fact]
    public async Task ByEinIndexesOnTheEchoedEinAndSkipsRecordsWithout()
    {
        var anonymous = Fixtures.Nonprofit(organization => organization.Remove("ein"));

        var handler = FakeHandler.Always(Stub.Json(
            Fixtures.Envelope(Fixtures.Organizations(Fixtures.Nonprofit(), anonymous))));
        using var client = Fixtures.Client(handler);

        var byEin = (await client.Nonprofits.CheckBulkAsync(new[] { "411787097" })).ByEin();

        Assert.Single(byEin);
        Assert.Equal("EXAMPLE NONPROFIT", byEin["411787097"].OrganizationName);
    }

    [Fact]
    public async Task ALeadingZeroEinSurvivesIndexing()
    {
        var organization = Fixtures.Nonprofit(o => o["ein"] = "042103594");

        var handler = FakeHandler.Always(
            Stub.Json(Fixtures.Envelope(Fixtures.Organizations(organization))));
        using var client = Fixtures.Client(handler);

        var byEin = (await client.Nonprofits.CheckBulkAsync(new[] { "042103594" })).ByEin();

        Assert.True(byEin.ContainsKey("042103594"));
    }

    [Fact]
    public async Task MissingEinsArriveAsNotFoundOnASuccessfulResponse()
    {
        var envelope = Fixtures.Envelope(
            Fixtures.Organizations(Fixtures.Nonprofit()),
            e => e["errors"] = new JsonArray
            {
                new JsonObject
                {
                    ["resource"] = "nonprofitcheckbulk",
                    ["reason"] = "No record found",
                    ["code"] = 404,
                    ["eins"] = new JsonArray { "996589560", "123456789" },
                },
            });

        var handler = FakeHandler.Always(Stub.Json(envelope));
        using var client = Fixtures.Client(handler);

        var result = await client.Nonprofits.CheckBulkAsync(
            new[] { "411787097", "996589560", "123456789" });

        Assert.Equal(200, result.Status);
        Assert.Equal(new[] { "996589560", "123456789" }, result.NotFoundEins);
        Assert.Equal("No record found", Assert.Single(result.Errors).Reason);
    }

    [Fact]
    public async Task ACommaSeparatedEinListIsNormalizedToAList()
    {
        var envelope = Fixtures.Envelope(
            new JsonArray(),
            e => e["errors"] = new JsonArray
            {
                new JsonObject { ["reason"] = "No record found", ["eins"] = "996589560, 123456789" },
            });

        var handler = FakeHandler.Always(Stub.Json(envelope));
        using var client = Fixtures.Client(handler);

        var result = await client.Nonprofits.CheckBulkAsync(new[] { "996589560" });

        Assert.Equal(new[] { "996589560", "123456789" }, result.NotFoundEins);
    }

    [Fact]
    public async Task AcceptsDataWrappedInAnOrganizationsObject()
    {
        var envelope = Fixtures.Envelope(new JsonObject
        {
            ["organizations"] = Fixtures.Organizations(Fixtures.Nonprofit()),
        });

        var handler = FakeHandler.Always(Stub.Json(envelope));
        using var client = Fixtures.Client(handler);

        var result = await client.Nonprofits.CheckBulkAsync(new[] { "411787097" });

        Assert.Equal("EXAMPLE NONPROFIT", Assert.Single(result.Organizations).OrganizationName);
    }
}
