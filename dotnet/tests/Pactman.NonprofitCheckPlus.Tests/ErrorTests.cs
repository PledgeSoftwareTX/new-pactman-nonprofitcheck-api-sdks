using System;
using System.Collections.Generic;
using System.Text.Json.Nodes;
using System.Threading.Tasks;
using Pactman.NonprofitCheckPlus.Configuration;
using Pactman.NonprofitCheckPlus.Exceptions;
using Pactman.NonprofitCheckPlus.Tests.Support;
using Xunit;

namespace Pactman.NonprofitCheckPlus.Tests;

public class ErrorTests
{
    [Theory]
    [InlineData(400, typeof(PactmanBadRequestException), ErrorCategory.BadRequest)]
    [InlineData(401, typeof(PactmanAuthenticationException), ErrorCategory.Authentication)]
    [InlineData(403, typeof(PactmanAuthorizationException), ErrorCategory.Authorization)]
    [InlineData(404, typeof(PactmanNotFoundException), ErrorCategory.NotFound)]
    [InlineData(429, typeof(PactmanRateLimitException), ErrorCategory.RateLimit)]
    [InlineData(500, typeof(PactmanServerException), ErrorCategory.Server)]
    [InlineData(503, typeof(PactmanServerException), ErrorCategory.Server)]
    [InlineData(418, typeof(PactmanApiException), ErrorCategory.Api)]
    public async Task MapsAStatusToItsExceptionAndCategory(int status, Type expected, ErrorCategory category)
    {
        using var client = Fixtures.Client(FakeHandler.Always(Stub.Error(status)), retry: RetryOptions.None);

        var error = await Assert.ThrowsAnyAsync<PactmanApiException>(
            () => client.Nonprofits.CheckAsync("411787097"));

        Assert.IsType(expected, error);
        Assert.Equal(category, error.Category);
        Assert.Equal(ErrorOrigin.Api, error.Origin);
        Assert.Equal(status, error.Status);
    }

    [Fact]
    public async Task EveryApiExceptionIsAPactmanException()
    {
        using var client = Fixtures.Client(FakeHandler.Always(Stub.Error(500)), retry: RetryOptions.None);

        var error = await Assert.ThrowsAnyAsync<PactmanException>(
            () => client.Nonprofits.CheckAsync("411787097"));

        Assert.True(PactmanException.IsPactmanError(error));
    }

    [Fact]
    public async Task PrefersTheReasonsFromTheErrorsArray()
    {
        var stub = Stub.Error(400, "generic message", new JsonArray
        {
            new JsonObject { ["reason"] = "EIN is malformed" },
            new JsonObject { ["reason"] = "EIN is unknown" },
        });

        using var client = Fixtures.Client(FakeHandler.Always(stub), retry: RetryOptions.None);

        var error = await Assert.ThrowsAsync<PactmanBadRequestException>(
            () => client.Nonprofits.CheckAsync("411787097"));

        Assert.Equal("EIN is malformed; EIN is unknown", error.Message);
        Assert.Equal(2, error.ApiErrors.Count);
    }

    [Fact]
    public async Task FallsBackToTheEnvelopeMessage()
    {
        using var client = Fixtures.Client(
            FakeHandler.Always(Stub.Error(403, "This key cannot read that resource.")),
            retry: RetryOptions.None);

        var error = await Assert.ThrowsAsync<PactmanAuthorizationException>(
            () => client.Nonprofits.CheckAsync("411787097"));

        Assert.Equal("This key cannot read that resource.", error.Message);
        Assert.Equal("This key cannot read that resource.", error.ApiMessage);
    }

    [Fact]
    public async Task FallsBackToADefaultMessageWhenTheApiSendsNone()
    {
        using var client = Fixtures.Client(
            FakeHandler.Always(Stub.Error(401)),
            retry: RetryOptions.None);

        var error = await Assert.ThrowsAsync<PactmanAuthenticationException>(
            () => client.Nonprofits.CheckAsync("411787097"));

        Assert.Equal("The Pactman API key was rejected.", error.Message);
        Assert.Null(error.ApiMessage);
    }

    [Fact]
    public async Task AnUnparseableErrorBodyIsKeptAsEvidence()
    {
        using var client = Fixtures.Client(
            FakeHandler.Always(Stub.Text("<html>502 Bad Gateway</html>", 502)),
            retry: RetryOptions.None);

        var error = await Assert.ThrowsAsync<PactmanServerException>(
            () => client.Nonprofits.CheckAsync("411787097"));

        Assert.Contains("502 Bad Gateway", error.Message, StringComparison.Ordinal);
        Assert.False(error.Raw.IsJson);
        Assert.Contains("502 Bad Gateway", error.Raw.Text!, StringComparison.Ordinal);
    }

    [Fact]
    public async Task CarriesTheCorrelationIdentifierAndAttemptCount()
    {
        var stub = Stub.Error(500, headers: new Dictionary<string, string> { ["x-correlation-id"] = "cor_7" });
        using var client = Fixtures.Client(
            FakeHandler.Always(stub),
            clock: new Clock(),
            retry: new RetryOptions { MaxRetries = 1 });

        var error = await Assert.ThrowsAsync<PactmanServerException>(
            () => client.Nonprofits.CheckAsync("411787097"));

        Assert.Equal("cor_7", error.RequestId);
        Assert.Equal(2, error.Attempts);
    }

    [Fact]
    public async Task RateLimitCarriesRetryAfter()
    {
        var stub = Stub.Error(429, headers: new Dictionary<string, string> { ["Retry-After"] = "12" });
        using var client = Fixtures.Client(FakeHandler.Always(stub), retry: RetryOptions.None);

        var error = await Assert.ThrowsAsync<PactmanRateLimitException>(
            () => client.Nonprofits.CheckAsync("411787097"));

        Assert.Equal(TimeSpan.FromSeconds(12), error.RetryAfter);
    }

    [Fact]
    public async Task ReadsTheEnvelopeCode()
    {
        var stub = Stub.Json(new JsonObject { ["code"] = 4001, ["message"] = "nope" }, 400);
        using var client = Fixtures.Client(FakeHandler.Always(stub), retry: RetryOptions.None);

        var error = await Assert.ThrowsAsync<PactmanBadRequestException>(
            () => client.Nonprofits.CheckAsync("411787097"));

        Assert.Equal(4001, error.ApiCode);
    }

    [Fact]
    public async Task AConnectionFailureBecomesANetworkError()
    {
        var handler = FakeHandler.Always(
            Stub.Failure(new System.Net.Http.HttpRequestException("connection refused")));
        using var client = Fixtures.Client(handler, retry: RetryOptions.None);

        var error = await Assert.ThrowsAsync<PactmanNetworkException>(
            () => client.Nonprofits.CheckAsync("411787097"));

        Assert.Equal(ErrorCategory.Network, error.Category);
        Assert.Equal(ErrorOrigin.Local, error.Origin);
        Assert.Contains("connection refused", error.Message, StringComparison.Ordinal);
        Assert.Equal(1, error.Attempts);
    }

    [Fact]
    public async Task NoDiagnosticEverCarriesTheApiKey()
    {
        using var client = Fixtures.Client(
            FakeHandler.Always(Stub.Error(401, "The Pactman API key was rejected.")),
            retry: RetryOptions.None);

        var error = await Assert.ThrowsAsync<PactmanAuthenticationException>(
            () => client.Nonprofits.CheckAsync("411787097"));

        var rendered = error.ToString() + "|" + string.Join(
            "|",
            System.Linq.Enumerable.Select(error.ToDictionary(), f => f.Key + "=" + f.Value));

        Assert.DoesNotContain(Fixtures.ApiKey, rendered, StringComparison.Ordinal);
    }

    [Fact]
    public async Task ToDictionaryCarriesTheStableWireValues()
    {
        using var client = Fixtures.Client(FakeHandler.Always(Stub.Error(429)), retry: RetryOptions.None);

        var error = await Assert.ThrowsAsync<PactmanRateLimitException>(
            () => client.Nonprofits.CheckAsync("411787097"));

        var fields = error.ToDictionary();

        Assert.Equal("rate_limit", fields["category"]);
        Assert.Equal("api", fields["origin"]);
        Assert.Equal(429, fields["status"]);
        Assert.Equal(nameof(PactmanRateLimitException), fields["name"]);
    }

    [Fact]
    public async Task ASingleErrorObjectIsNormalizedToAList()
    {
        var stub = Stub.Error(400, errors: new JsonObject { ["reason"] = "just the one" });
        using var client = Fixtures.Client(FakeHandler.Always(stub), retry: RetryOptions.None);

        var error = await Assert.ThrowsAsync<PactmanBadRequestException>(
            () => client.Nonprofits.CheckAsync("411787097"));

        Assert.Equal("just the one", Assert.Single(error.ApiErrors).Reason);
    }

    [Fact]
    public async Task AStringErrorsFieldIsNormalizedToAList()
    {
        var stub = Stub.Json(new JsonObject { ["code"] = 400, ["errors"] = "everything is wrong" }, 400);
        using var client = Fixtures.Client(FakeHandler.Always(stub), retry: RetryOptions.None);

        var error = await Assert.ThrowsAsync<PactmanBadRequestException>(
            () => client.Nonprofits.CheckAsync("411787097"));

        Assert.Equal("everything is wrong", Assert.Single(error.ApiErrors).Reason);
        Assert.Equal("everything is wrong", error.Message);
    }
}
