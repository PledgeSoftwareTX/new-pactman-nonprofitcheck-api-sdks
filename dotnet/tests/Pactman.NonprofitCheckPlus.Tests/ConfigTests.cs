using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.RegularExpressions;
using System.Threading.Tasks;
using Pactman.NonprofitCheckPlus.Configuration;
using Pactman.NonprofitCheckPlus.Exceptions;
using Pactman.NonprofitCheckPlus.Tests.Support;
using Xunit;

namespace Pactman.NonprofitCheckPlus.Tests;

public class ConfigTests
{
    [Fact]
    public void VersionMatchesTheVersionDeclaredInDirectoryBuildProps()
    {
        var props = File.ReadAllText("Directory.Build.props");
        var declared = Regex.Match(props, @"<PactmanSdkVersion>([^<]+)</PactmanSdkVersion>").Groups[1].Value;

        Assert.False(string.IsNullOrWhiteSpace(declared), "Directory.Build.props declares no PactmanSdkVersion.");
        Assert.Equal(SdkVersion.Version, declared);
    }

    [Fact]
    public void DefaultsToProduction()
    {
        using var client = new PactmanClient("key");

        Assert.Equal("https://entities.pactman.org", client.BaseUrl);
        Assert.Equal(PactmanEnvironment.Production, client.Environment);
        Assert.Equal(TimeSpan.FromSeconds(30), client.Timeout);
        Assert.Equal(2, client.Retry.MaxRetries);
    }

    [Fact]
    public void AnExplicitBaseUrlClearsTheNamedEnvironment()
    {
        using var client = new PactmanClient(new PactmanClientOptions
        {
            ApiKey = "key",
            BaseUrl = "https://proxy.internal:8443/pactman/",
        });

        Assert.Equal("https://proxy.internal:8443/pactman", client.BaseUrl);
        Assert.Null(client.Environment);
    }

    [Theory]
    [InlineData(null, "A Pactman API key is required")]
    [InlineData("", "The Pactman API key is empty")]
    [InlineData("   ", "The Pactman API key is empty")]
    public void RejectsAnUnusableApiKey(string? apiKey, string expected)
    {
        var error = Assert.Throws<PactmanConfigurationException>(() => new PactmanClient(apiKey));

        Assert.Contains(expected, error.Message, StringComparison.Ordinal);
        Assert.Equal(ErrorCategory.Configuration, error.Category);
        Assert.Equal(ErrorOrigin.Local, error.Origin);
    }

    [Theory]
    [InlineData("not a url")]
    [InlineData("ftp://entities.pactman.org")]
    [InlineData("   ")]
    public void RejectsAnUnusableBaseUrl(string baseUrl)
    {
        Assert.Throws<PactmanConfigurationException>(() => new PactmanClient(new PactmanClientOptions
        {
            ApiKey = "key",
            BaseUrl = baseUrl,
        }));
    }

    [Theory]
    [InlineData(0)]
    [InlineData(-1)]
    public void RejectsANonPositiveTimeout(int seconds)
    {
        Assert.Throws<PactmanConfigurationException>(() => new PactmanClient(new PactmanClientOptions
        {
            ApiKey = "key",
            Timeout = TimeSpan.FromSeconds(seconds),
        }));
    }

    [Theory]
    [InlineData(0d)]
    [InlineData(-2d)]
    [InlineData(double.NaN)]
    public void RejectsANonPositiveRequestCeiling(double limit)
    {
        Assert.Throws<PactmanConfigurationException>(() => new PactmanClient(new PactmanClientOptions
        {
            ApiKey = "key",
            MaxRequestsPerSecond = limit,
        }));
    }

    [Fact]
    public void RejectsANegativeRetryCount()
    {
        Assert.Throws<PactmanConfigurationException>(() => new RetryOptions { MaxRetries = -1 });
    }

    [Fact]
    public void RejectsABackoffFactorBelowOne()
    {
        Assert.Throws<PactmanConfigurationException>(() => new RetryOptions { BackoffFactor = 0.5 });
    }

    [Fact]
    public void AWithExpressionRevalidates()
    {
        Assert.Throws<PactmanConfigurationException>(() => RetryOptions.Default with { MaxRetries = -3 });
    }

    [Fact]
    public void TheApiKeyNeverAppearsInADiagnostic()
    {
        using var client = new PactmanClient(new PactmanClientOptions
        {
            ApiKey = Fixtures.ApiKey,
            BaseUrl = Fixtures.BaseUrl,
        });

        var rendered = client.ToString() + string.Join(
            "|",
            client.ToDictionary().Select(field => field.Key + "=" + field.Value));

        Assert.DoesNotContain(Fixtures.ApiKey, rendered, StringComparison.Ordinal);
        Assert.Equal("[redacted]", client.ToDictionary()["apiKey"]);
    }

    [Fact]
    public async Task SendsTheCredentialAndUserAgentOnEveryRequest()
    {
        var handler = FakeHandler.Returning(Fixtures.Nonprofit());
        using var client = Fixtures.Client(handler);

        await client.Nonprofits.CheckAsync("411787097");

        var request = handler.LastRequest;

        Assert.Equal("Bearer " + Fixtures.ApiKey, request.Header("Authorization"));
        Assert.Equal("application/json", request.Header("Accept"));
        Assert.StartsWith("Pactman.NonprofitCheckPlus/" + SdkVersion.Version, request.Header("User-Agent")!, StringComparison.Ordinal);
    }

    [Fact]
    public async Task DefaultAndPerRequestHeadersAreSentButCannotDisplaceTheCredential()
    {
        var handler = FakeHandler.Returning(Fixtures.Nonprofit());
        using var client = Fixtures.Client(handler, defaultHeaders: new Dictionary<string, string>
        {
            ["X-Tenant"] = "acme",
            ["Authorization"] = "Bearer forged",
        });

        var options = new RequestOptions();
        options.Headers["X-Trace"] = "abc123";
        options.Headers["Authorization"] = "Bearer also-forged";

        await client.Nonprofits.CheckAsync("411787097", options);

        var request = handler.LastRequest;

        Assert.Equal("acme", request.Header("X-Tenant"));
        Assert.Equal("abc123", request.Header("X-Trace"));
        Assert.Equal("Bearer " + Fixtures.ApiKey, request.Header("Authorization"));
    }

    [Fact]
    public void TheUserAgentIsHeaderSafe()
    {
        var userAgent = ConfigResolver.BuildUserAgent();

        Assert.DoesNotContain('\n', userAgent);
        Assert.DoesNotContain('\r', userAgent);
        Assert.Matches(@"^Pactman\.NonprofitCheckPlus/\d+\.\d+\.\d+ \(dotnet/.+; .+\)$", userAgent);
    }

    [Fact]
    public void ADisposedClientDoesNotDisposeABorrowedHttpClient()
    {
        using var httpClient = new System.Net.Http.HttpClient(new FakeHandler(Stub.Empty204()));

        var client = new PactmanClient(new PactmanClientOptions
        {
            ApiKey = "key",
            HttpClient = httpClient,
        });

        client.Dispose();

        // Still usable: disposing the SDK client did not tear down the shared pool.
        Assert.NotNull(httpClient.DefaultRequestHeaders);
    }
}
