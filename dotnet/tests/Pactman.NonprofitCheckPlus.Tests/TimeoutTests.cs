using System;
using System.Threading;
using System.Threading.Tasks;
using Pactman.NonprofitCheckPlus.Configuration;
using Pactman.NonprofitCheckPlus.Exceptions;
using Pactman.NonprofitCheckPlus.Tests.Support;
using Xunit;

namespace Pactman.NonprofitCheckPlus.Tests;

public class TimeoutTests
{
    private static readonly TimeSpan ShortDeadline = TimeSpan.FromMilliseconds(30);

    [Fact]
    public async Task AnExpiredDeadlineBecomesATimeoutError()
    {
        var handler = FakeHandler.Always(Stub.Hangs(TimeSpan.FromSeconds(30)));
        var clock = new Clock();
        using var client = Fixtures.Client(handler, clock, timeout: ShortDeadline, retry: RetryOptions.None);

        var error = await Assert.ThrowsAsync<PactmanTimeoutException>(
            () => client.Nonprofits.CheckAsync("411787097"));

        Assert.Equal(ErrorCategory.Timeout, error.Category);
        Assert.Equal(ErrorOrigin.Local, error.Origin);
        Assert.Equal(ShortDeadline, error.Timeout);
        Assert.Equal(1, error.Attempts);
    }

    [Fact]
    public async Task ATimeoutIsRetriedWhenThePolicyAllowsIt()
    {
        var handler = new FakeHandler(
            Stub.Hangs(TimeSpan.FromSeconds(30)),
            Stub.Json(Fixtures.Envelope(Fixtures.Nonprofit())));

        var clock = new Clock();
        using var client = Fixtures.Client(handler, clock, timeout: ShortDeadline);

        var result = await client.Nonprofits.CheckAsync("411787097");

        Assert.Equal(200, result.Status);
        Assert.Equal(2, handler.RequestCount);
    }

    [Fact]
    public async Task APerRequestTimeoutOverridesTheClients()
    {
        var handler = FakeHandler.Always(Stub.Hangs(TimeSpan.FromSeconds(30)));
        var clock = new Clock();
        using var client = Fixtures.Client(handler, clock, timeout: TimeSpan.FromSeconds(30), retry: RetryOptions.None);

        var error = await Assert.ThrowsAsync<PactmanTimeoutException>(() => client.Nonprofits.CheckAsync(
            "411787097",
            new RequestOptions { Timeout = ShortDeadline }));

        Assert.Equal(ShortDeadline, error.Timeout);
    }

    [Fact]
    public async Task TheCallersOwnCancellationIsNotDressedUpAsATimeout()
    {
        var handler = FakeHandler.Always(Stub.Hangs(TimeSpan.FromSeconds(30)));
        var clock = new Clock();
        using var client = Fixtures.Client(handler, clock, timeout: TimeSpan.FromSeconds(30));

        using var cancellation = new CancellationTokenSource(ShortDeadline);

        var error = await Assert.ThrowsAnyAsync<OperationCanceledException>(
            () => client.Nonprofits.CheckAsync("411787097", cancellationToken: cancellation.Token));

        Assert.IsNotType<PactmanTimeoutException>(error);
        Assert.False(PactmanException.IsPactmanError(error));
    }

    [Fact]
    public async Task AnAlreadyCancelledTokenSendsNothing()
    {
        var handler = FakeHandler.Returning(Fixtures.Nonprofit());
        using var client = Fixtures.Client(handler);

        using var cancellation = new CancellationTokenSource();
        cancellation.Cancel();

        await Assert.ThrowsAnyAsync<OperationCanceledException>(
            () => client.Nonprofits.CheckAsync("411787097", cancellationToken: cancellation.Token));

        Assert.Equal(0, handler.RequestCount);
    }
}
