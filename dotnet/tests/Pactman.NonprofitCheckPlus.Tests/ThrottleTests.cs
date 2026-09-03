using System;
using System.Linq;
using System.Threading.Tasks;
using Pactman.NonprofitCheckPlus.Tests.Support;
using Xunit;

namespace Pactman.NonprofitCheckPlus.Tests;

public class ThrottleTests
{
    [Fact]
    public async Task NoCeilingMeansNoSpacing()
    {
        var handler = FakeHandler.Returning(Fixtures.Nonprofit());
        var clock = new Clock();
        using var client = Fixtures.Client(handler, clock);

        await client.Nonprofits.CheckAsync("411787097");
        await client.Nonprofits.CheckAsync("411787097");

        Assert.Empty(clock.Delays);
    }

    [Fact]
    public async Task RequestsAreSpacedToTheConfiguredCeiling()
    {
        var handler = FakeHandler.Returning(Fixtures.Nonprofit());
        var clock = new Clock();
        using var client = Fixtures.Client(handler, clock, maxRequestsPerSecond: 2);

        for (var i = 0; i < 3; i++)
        {
            await client.Nonprofits.CheckAsync("411787097");
        }

        // The first request goes immediately; each later one waits out the interval.
        Assert.Equal(2, clock.Delays.Count);
        Assert.All(clock.Delays, delay => Assert.Equal(TimeSpan.FromSeconds(0.5), delay));
    }

    [Fact]
    public async Task ARetryIsThrottledLikeAnyOtherRequest()
    {
        var handler = new FakeHandler(
            Stub.Error(503),
            Stub.Json(Fixtures.Envelope(Fixtures.Nonprofit())));

        var clock = new Clock(randomValue: 0.0);
        using var client = Fixtures.Client(handler, clock, maxRequestsPerSecond: 1);

        await client.Nonprofits.CheckAsync("411787097");

        // One backoff delay (zeroed by the jitter source) plus one throttle interval.
        Assert.Equal(2, handler.RequestCount);
        Assert.Contains(TimeSpan.FromSeconds(1), clock.Delays);
    }
}
