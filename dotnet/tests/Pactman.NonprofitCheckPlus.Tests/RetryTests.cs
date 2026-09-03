using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using Pactman.NonprofitCheckPlus.Configuration;
using Pactman.NonprofitCheckPlus.Exceptions;
using Pactman.NonprofitCheckPlus.Http;
using Pactman.NonprofitCheckPlus.Tests.Support;
using Xunit;

namespace Pactman.NonprofitCheckPlus.Tests;

public class RetryTests
{
    [Fact]
    public async Task RetriesARetryableStatusAndSucceeds()
    {
        var handler = new FakeHandler(
            Stub.Error(503),
            Stub.Error(503),
            Stub.Json(Fixtures.Envelope(Fixtures.Nonprofit())));

        var clock = new Clock();
        using var client = Fixtures.Client(handler, clock);

        var result = await client.Nonprofits.CheckAsync("411787097");

        Assert.Equal(200, result.Status);
        Assert.Equal(3, handler.RequestCount);
        Assert.Equal(2, clock.Delays.Count);
    }

    [Fact]
    public async Task GivesUpAfterMaxRetries()
    {
        var handler = FakeHandler.Always(Stub.Error(503));
        var clock = new Clock();
        using var client = Fixtures.Client(handler, clock, retry: new RetryOptions { MaxRetries = 3 });

        var error = await Assert.ThrowsAsync<PactmanServerException>(
            () => client.Nonprofits.CheckAsync("411787097"));

        Assert.Equal(4, handler.RequestCount);
        Assert.Equal(4, error.Attempts);
        Assert.Equal(3, clock.Delays.Count);
    }

    [Theory]
    [InlineData(400)]
    [InlineData(401)]
    [InlineData(403)]
    [InlineData(404)]
    public async Task NeverRetriesAClientError(int status)
    {
        var handler = FakeHandler.Always(Stub.Error(status));
        var clock = new Clock();
        using var client = Fixtures.Client(handler, clock, retry: new RetryOptions { MaxRetries = 5 });

        await Assert.ThrowsAnyAsync<PactmanApiException>(() => client.Nonprofits.CheckAsync("411787097"));

        Assert.Equal(1, handler.RequestCount);
        Assert.Empty(clock.Delays);
    }

    [Fact]
    public async Task AStatusOutsideThePolicyIsNotRetried()
    {
        var handler = FakeHandler.Always(Stub.Error(418));
        var clock = new Clock();
        using var client = Fixtures.Client(handler, clock, retry: new RetryOptions { MaxRetries = 5 });

        await Assert.ThrowsAsync<PactmanApiException>(() => client.Nonprofits.CheckAsync("411787097"));

        Assert.Equal(1, handler.RequestCount);
    }

    [Fact]
    public async Task NeverRetryStatusesHoldEvenWhenListedAsRetryable()
    {
        var handler = FakeHandler.Always(Stub.Error(404));
        var clock = new Clock();
        using var client = Fixtures.Client(
            handler,
            clock,
            retry: new RetryOptions { MaxRetries = 5, RetryableStatuses = new[] { 404, 500 } });

        await Assert.ThrowsAsync<PactmanNotFoundException>(() => client.Nonprofits.CheckAsync("411787097"));

        Assert.Equal(1, handler.RequestCount);
    }

    [Fact]
    public async Task RetriesAConnectionFailure()
    {
        var handler = new FakeHandler(
            Stub.Failure(new System.Net.Http.HttpRequestException("connection reset")),
            Stub.Json(Fixtures.Envelope(Fixtures.Nonprofit())));

        var clock = new Clock();
        using var client = Fixtures.Client(handler, clock);

        var result = await client.Nonprofits.CheckAsync("411787097");

        Assert.Equal(200, result.Status);
        Assert.Equal(2, handler.RequestCount);
    }

    [Fact]
    public async Task RetryOptionsNoneDisablesRetrying()
    {
        var handler = FakeHandler.Always(Stub.Error(503));
        var clock = new Clock();
        using var client = Fixtures.Client(handler, clock);

        await Assert.ThrowsAsync<PactmanServerException>(
            () => client.Nonprofits.CheckAsync("411787097", new RequestOptions { Retry = RetryOptions.None }));

        Assert.Equal(1, handler.RequestCount);
    }

    [Fact]
    public async Task APerRequestPolicyOverridesTheClients()
    {
        var handler = FakeHandler.Always(Stub.Error(503));
        var clock = new Clock();
        using var client = Fixtures.Client(handler, clock, retry: RetryOptions.None);

        await Assert.ThrowsAsync<PactmanServerException>(() => client.Nonprofits.CheckAsync(
            "411787097",
            new RequestOptions { Retry = client.Retry with { MaxRetries = 2 } }));

        Assert.Equal(3, handler.RequestCount);
    }

    [Fact]
    public async Task HonorsRetryAfterOverBackoff()
    {
        var handler = new FakeHandler(
            Stub.Error(429, headers: new Dictionary<string, string> { ["Retry-After"] = "7" }),
            Stub.Json(Fixtures.Envelope(Fixtures.Nonprofit())));

        var clock = new Clock();
        using var client = Fixtures.Client(handler, clock);

        await client.Nonprofits.CheckAsync("411787097");

        Assert.Equal(TimeSpan.FromSeconds(7), Assert.Single(clock.Delays));
    }

    [Fact]
    public async Task IgnoresRetryAfterWhenTheOptionIsOff()
    {
        var handler = new FakeHandler(
            Stub.Error(429, headers: new Dictionary<string, string> { ["Retry-After"] = "600" }),
            Stub.Json(Fixtures.Envelope(Fixtures.Nonprofit())));

        var clock = new Clock();
        using var client = Fixtures.Client(
            handler,
            clock,
            retry: new RetryOptions { RespectRetryAfter = false, Jitter = false });

        await client.Nonprofits.CheckAsync("411787097");

        Assert.Equal(TimeSpan.FromMilliseconds(500), Assert.Single(clock.Delays));
    }

    [Fact]
    public void BackoffGrowsExponentiallyAndIsCapped()
    {
        var policy = new RetryOptions { Jitter = false, InitialDelay = TimeSpan.FromSeconds(1), MaxDelay = TimeSpan.FromSeconds(5) };

        var delays = Enumerable.Range(1, 5)
            .Select(attempt => Transport.ComputeRetryDelay(attempt, policy, null).TotalSeconds)
            .ToArray();

        Assert.Equal(new[] { 1d, 2d, 4d, 5d, 5d }, delays);
    }

    [Fact]
    public void FullJitterSpreadsAcrossTheWholeRange()
    {
        var policy = new RetryOptions { InitialDelay = TimeSpan.FromSeconds(1), MaxDelay = TimeSpan.FromSeconds(8) };

        Assert.Equal(TimeSpan.Zero, Transport.ComputeRetryDelay(3, policy, null, () => 0.0));
        Assert.Equal(TimeSpan.FromSeconds(4), Transport.ComputeRetryDelay(3, policy, null, () => 1.0));
        Assert.Equal(TimeSpan.FromSeconds(2), Transport.ComputeRetryDelay(3, policy, null, () => 0.5));
    }

    [Fact]
    public void ANegativeRetryAfterFallsBackToBackoff()
    {
        var policy = new RetryOptions { Jitter = false, InitialDelay = TimeSpan.FromSeconds(1) };

        Assert.Equal(
            TimeSpan.FromSeconds(1),
            Transport.ComputeRetryDelay(1, policy, TimeSpan.FromSeconds(-5)));
    }
}
