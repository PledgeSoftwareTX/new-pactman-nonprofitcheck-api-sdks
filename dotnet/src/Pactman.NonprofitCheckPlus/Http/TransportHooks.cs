using System;
using System.Threading;
using System.Threading.Tasks;

namespace Pactman.NonprofitCheckPlus.Http
{
    /// <summary>
    /// Seam for injecting a clock into tests, so retry and throttle tests run instantly
    /// instead of actually waiting.
    /// </summary>
    /// <remarks>
    /// Internal, and not covered by semantic versioning.
    /// </remarks>
    internal sealed class TransportHooks
    {
        /// <summary>Called instead of waiting, with the delay that would have elapsed.</summary>
        public Func<TimeSpan, CancellationToken, Task>? Delay { get; set; }

        /// <summary>Returns a value in <c>[0, 1)</c>. Used for backoff jitter.</summary>
        public Func<double>? Random { get; set; }

        /// <summary>Returns a monotonically increasing time in seconds. Used for throttling.</summary>
        public Func<double>? Monotonic { get; set; }
    }
}
