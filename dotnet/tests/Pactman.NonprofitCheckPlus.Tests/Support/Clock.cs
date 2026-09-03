using System;
using System.Collections.Generic;
using System.Threading;
using System.Threading.Tasks;
using Pactman.NonprofitCheckPlus.Http;

namespace Pactman.NonprofitCheckPlus.Tests.Support;

/// <summary>Records requested delays instead of waiting, so retry tests stay instant.</summary>
public sealed class Clock
{
    private double _now;

    public Clock(double randomValue = 1.0) => RandomValue = randomValue;

    /// <summary>The value the transport's jitter source returns.</summary>
    public double RandomValue { get; set; }

    /// <summary>Every delay the transport asked for, in order.</summary>
    public List<TimeSpan> Delays { get; } = new();

    /// <summary>Total time the transport believes has passed.</summary>
    public TimeSpan Elapsed => TimeSpan.FromSeconds(_now);

    internal TransportHooks Hooks() => new()
    {
        Delay = (duration, _) =>
        {
            Delays.Add(duration);
            _now += duration.TotalSeconds;

            return Task.CompletedTask;
        },
        Random = () => RandomValue,
        Monotonic = () => _now,
    };
}
