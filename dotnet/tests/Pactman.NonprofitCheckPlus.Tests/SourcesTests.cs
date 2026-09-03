using System;
using System.Threading.Tasks;
using Pactman.NonprofitCheckPlus.Models;
using Pactman.NonprofitCheckPlus.Tests.Support;
using Xunit;

namespace Pactman.NonprofitCheckPlus.Tests;

public class SourcesTests
{
    private static async Task<Nonprofit> Organization(Action<System.Text.Json.Nodes.JsonObject>? customize = null)
    {
        using var client = Fixtures.Client(FakeHandler.Returning(Fixtures.Nonprofit(customize)));

        return (await client.Nonprofits.CheckAsync("411787097")).Nonprofit!;
    }

    [Fact]
    public async Task ProjectsPublication78Findings()
    {
        var pub78 = (await Organization()).Pub78()!;

        Assert.True(pub78.Verified);
        Assert.Equal("Example Nonprofit", pub78.OrganizationName);
        Assert.Equal("411787097", pub78.Ein);
        Assert.Equal("Westfield", pub78.City);
        Assert.Equal("MA", pub78.State);
        Assert.Equal("0", pub78.Indicator);
        Assert.Equal("12/12/2025 12:00:00 AM", pub78.MostRecent);
    }

    [Fact]
    public async Task ProjectsBusinessMasterFileFindings()
    {
        var bmf = (await Organization()).Bmf()!;

        Assert.True(bmf.Status);
        Assert.Equal("EXAMPLE NONPROFIT", bmf.OrganizationName);
        Assert.Equal("03", bmf.Subsection);
        Assert.Equal("501(c)(3) Public Charity", bmf.SubsectionDescription);
        Assert.Equal("10", bmf.FoundationCode);
        Assert.Equal("2024", bmf.RulingYear);
        Assert.Equal("00", bmf.FilingReqCode);
    }

    [Fact]
    public async Task ProjectsOfacFindings()
    {
        var ofac = (await Organization()).Ofac()!;

        Assert.StartsWith("This organization was NOT included", ofac.Status!, StringComparison.Ordinal);
    }

    [Fact]
    public async Task ProjectsRevocationFindings()
    {
        var aroe = (await Organization()).Aroe()!;

        Assert.True(aroe.Has("revocation_code"));
        Assert.Null(aroe.RevocationCode);
        Assert.Null(aroe.RevocationDate);
    }

    [Fact]
    public async Task ASourceTheApiDidNotReturnAtAllIsNull()
    {
        var organization = await Organization(o =>
        {
            o.Remove("ofac_status");
        });

        Assert.Null(organization.Ofac());
        Assert.NotNull(organization.Pub78());
    }

    [Fact]
    public async Task AnExplicitFalseIsNotMistakenForAbsence()
    {
        var organization = await Organization(o => o["pub78_verified"] = false);

        var pub78 = organization.Pub78()!;

        Assert.True(pub78.Has("verified"));
        Assert.False(pub78.Verified);
    }

    [Fact]
    public async Task AnExplicitNullIsNotMistakenForAbsence()
    {
        var organization = await Organization(o => o["ofac_status"] = null);

        var ofac = organization.Ofac()!;

        Assert.True(ofac.Has("status"));
        Assert.Null(ofac.Status);
    }

    [Fact]
    public async Task OnlyTheKeysTheApiReturnedArePresent()
    {
        var organization = await Organization(o => o.Remove("pub78_city"));

        var pub78 = organization.Pub78()!;

        Assert.False(pub78.Has("city"));
        Assert.True(pub78.Has("state"));
    }

    [Fact]
    public async Task TheExtensionAndStaticFormsAreTheSameCall()
    {
        var organization = await Organization();

        Assert.Equal(organization.Pub78()!.ToJson(), Sources.Pub78(organization)!.ToJson());
    }

    [Fact]
    public async Task AProjectionNeverInventsAVerdict()
    {
        var organization = await Organization();
        var bmf = organization.Bmf()!;

        // Every key is copied 1:1 from a field the API returned; nothing is derived.
        foreach (var field in bmf.FieldNames)
        {
            Assert.True(
                bmf.GetElement(field)!.Value.GetRawText().Length > 0,
                $"Projected field '{field}' has no backing value.");
        }
    }
}
