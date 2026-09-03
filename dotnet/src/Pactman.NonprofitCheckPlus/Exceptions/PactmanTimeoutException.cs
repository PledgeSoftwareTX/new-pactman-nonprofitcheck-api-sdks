using System;
using System.Collections.Generic;

using Pactman.NonprofitCheckPlus.Internal;

namespace Pactman.NonprofitCheckPlus.Exceptions
{
    /// <summary>
    /// The request exceeded the configured timeout.
    /// </summary>
    /// <remarks>
    /// Raised only when the SDK's own deadline expired. A <see cref="System.Threading.CancellationToken"/>
    /// you cancelled surfaces as <see cref="OperationCanceledException"/> instead, so
    /// "I gave up" stays distinguishable from "the API was too slow".
    /// </remarks>
    public sealed class PactmanTimeoutException : PactmanException
    {
        /// <summary>Initializes the exception.</summary>
        /// <param name="message">A description naming the deadline that elapsed.</param>
        /// <param name="timeout">The timeout that elapsed.</param>
        /// <param name="attempts">How many attempts were made before this error was surfaced.</param>
        /// <param name="innerException">The underlying cancellation or transport failure.</param>
        public PactmanTimeoutException(
            string message,
            TimeSpan timeout,
            int attempts = 1,
            Exception? innerException = null)
            : base(message, ErrorCategory.Timeout, ErrorOrigin.Local, innerException)
        {
            Timeout = timeout;
            Attempts = attempts;
        }

        /// <summary>The timeout that elapsed.</summary>
        public TimeSpan Timeout { get; }

        /// <summary>How many attempts were made before this error was surfaced.</summary>
        public int Attempts { get; }

        /// <inheritdoc />
        public override IReadOnlyDictionary<string, object?> ToDictionary() =>
            new FieldMap(base.ToDictionary())
            {
                ["timeout"] = Timeout.TotalSeconds,
                ["attempts"] = Attempts,
            };
    }
}
