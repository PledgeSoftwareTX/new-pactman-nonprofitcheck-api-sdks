using System;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Threading.Tasks;
using Pactman.NonprofitCheckPlus.Exceptions;
using Pactman.NonprofitCheckPlus.Tests.Support;
using Xunit;

namespace Pactman.NonprofitCheckPlus.Tests;

public class CheckTests
{
    [Fact]
    public async Task SendsTheNormalizedEinOnThePublishedPath()
    {
        var handler = FakeHandler.Returning(Fixtures.Nonprofit());
        using var client = Fixtures.Client(handler);

        await client.Nonprofits.CheckAsync("41-1787097");

        Assert.Equal("GET", handler.LastRequest.Method);
        Assert.Equal("/api/entities/nonprofitcheck/v1/us/ein/411787097", handler.LastRequest.Path);
        Assert.Null(handler.LastRequest.Body);
    }

    [Fact]
    public async Task AMalformedEinNeverReachesTheNetwork()
    {
        var handler = FakeHandler.Returning(Fixtures.Nonprofit());
        using var client = Fixtures.Client(handler);

        await Assert.ThrowsAsync<PactmanValidationException>(() => client.Nonprofits.CheckAsync("nope"));

        Assert.Equal(0, handler.RequestCount);
    }

    [Fact]
    public async Task ReadsTheOrganizationAndTheEnvelopeMetadata()
    {
        var handler = FakeHandler.Returning(Fixtures.Nonprofit());
        using var client = Fixtures.Client(handler);

        var result = await client.Nonprofits.CheckAsync("411787097");

        Assert.Equal(200, result.Status);
        Assert.Equal(1, result.CheckCount);
        Assert.Equal(3d, result.TimeTakenMs);
        Assert.Empty(result.Errors);
        Assert.Equal("EXAMPLE NONPROFIT", result.Nonprofit!.OrganizationName);
        Assert.Equal("411787097", result.Nonprofit.Ein);
        Assert.True(result.Nonprofit.Pub78Verified);
        Assert.False(result.Nonprofit.IrsBmfPub78Conflict);
    }

    [Fact]
    public async Task AcceptsDataDeliveredAsASingleElementArray()
    {
        var handler = FakeHandler.Always(
            Stub.Json(Fixtures.Envelope(Fixtures.Organizations(Fixtures.Nonprofit()))));
        using var client = Fixtures.Client(handler);

        var result = await client.Nonprofits.CheckAsync("411787097");

        Assert.Equal("EXAMPLE NONPROFIT", result.Nonprofit!.OrganizationName);
    }

    [Theory]
    [InlineData("null")]
    [InlineData("[]")]
    [InlineData("{}")]
    public async Task NoRecordYieldsANullOrganizationRatherThanAnError(string data)
    {
        var handler = FakeHandler.Always(Stub.Json(Fixtures.Envelope(JsonNode.Parse(data))));
        using var client = Fixtures.Client(handler);

        var result = await client.Nonprofits.CheckAsync("411787097");

        Assert.Null(result.Nonprofit);
        Assert.Equal(200, result.Status);
    }

    [Fact]
    public async Task AFieldReturnedAsNullIsDistinguishableFromOneNeverReturned()
    {
        var handler = FakeHandler.Returning(Fixtures.Nonprofit(organization =>
        {
            organization["address_line2"] = null;
            organization.Remove("organization_name_aka");
        }));
        using var client = Fixtures.Client(handler);

        var organization = (await client.Nonprofits.CheckAsync("411787097")).Nonprofit!;

        Assert.True(organization.Has("address_line2"));
        Assert.Null(organization.AddressLine2);

        Assert.False(organization.Has("organization_name_aka"));
        Assert.Null(organization.OrganizationNameAka);
    }

    [Fact]
    public async Task AFieldThisReleaseDoesNotDeclareIsStillReadable()
    {
        var handler = FakeHandler.Returning(Fixtures.Nonprofit(organization =>
        {
            organization["some_future_field"] = "tomorrow";
        }));
        using var client = Fixtures.Client(handler);

        var organization = (await client.Nonprofits.CheckAsync("411787097")).Nonprofit!;

        Assert.True(organization.Has("some_future_field"));
        Assert.Equal("tomorrow", organization.GetString("some_future_field"));
        Assert.Equal("tomorrow", organization["some_future_field"]!.Value.GetString());
    }

    [Fact]
    public async Task OrganizationTypesDropsUnresolvableEntries()
    {
        var handler = FakeHandler.Returning(Fixtures.Nonprofit(organization =>
        {
            organization["organization_types"] = new JsonArray
            {
                null,
                new JsonObject { ["organization_type"] = "PC", ["deductibility_limitation"] = "50%" },
            };
        }));
        using var client = Fixtures.Client(handler);

        var organization = (await client.Nonprofits.CheckAsync("411787097")).Nonprofit!;

        var entry = Assert.Single(organization.OrganizationTypes);
        Assert.Equal("PC", entry.Type);
        Assert.Equal("50%", entry.DeductibilityLimitation);
    }

    [Fact]
    public async Task OrganizationTypesIsEmptyWhenTheApiSentNone()
    {
        var handler = FakeHandler.Returning(Fixtures.Nonprofit(organization =>
        {
            organization.Remove("organization_types");
        }));
        using var client = Fixtures.Client(handler);

        var organization = (await client.Nonprofits.CheckAsync("411787097")).Nonprofit!;

        Assert.Empty(organization.OrganizationTypes);
        Assert.False(organization.Has("organization_types"));
    }

    [Fact]
    public async Task TheRawEnvelopeIsPreserved()
    {
        var handler = FakeHandler.Returning(Fixtures.Nonprofit());
        using var client = Fixtures.Client(handler);

        var result = await client.Nonprofits.CheckAsync("411787097");

        Assert.True(result.Raw.IsJson);
        Assert.Equal("OK", result.Raw.Envelope.GetProperty("message").GetString());
    }

    [Fact]
    public async Task ASuccessfulNonJsonBodyKeepsTheTextAsEvidence()
    {
        var handler = FakeHandler.Always(Stub.Text("<html>upstream said hello</html>"));
        using var client = Fixtures.Client(handler);

        var result = await client.Nonprofits.CheckAsync("411787097");

        Assert.False(result.Raw.IsJson);
        Assert.Contains("upstream said hello", result.Raw.Text!, StringComparison.Ordinal);
        Assert.Null(result.Nonprofit);
    }

    [Fact]
    public async Task ReadsTheCorrelationIdentifier()
    {
        var handler = FakeHandler.Always(Stub.Json(
            Fixtures.Envelope(Fixtures.Nonprofit()),
            headers: new System.Collections.Generic.Dictionary<string, string> { ["x-request-id"] = "req_42" }));
        using var client = Fixtures.Client(handler);

        var result = await client.Nonprofits.CheckAsync("411787097");

        Assert.Equal("req_42", result.RequestId);
    }

    [Fact]
    public async Task TheDataObjectRoundTripsToJson()
    {
        var handler = FakeHandler.Returning(Fixtures.Nonprofit());
        using var client = Fixtures.Client(handler);

        var organization = (await client.Nonprofits.CheckAsync("411787097")).Nonprofit!;

        using var reparsed = JsonDocument.Parse(organization.ToJson());

        Assert.Equal("EXAMPLE NONPROFIT", reparsed.RootElement.GetProperty("organization_name").GetString());
        Assert.Equal(JsonValueKind.Null, reparsed.RootElement.GetProperty("revocation_code").ValueKind);
    }
}
