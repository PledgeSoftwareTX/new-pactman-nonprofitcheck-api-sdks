using System;
using System.Collections.Generic;

using Pactman.NonprofitCheckPlus.Internal;

namespace Pactman.NonprofitCheckPlus.Exceptions
{
    /// <summary>The request produced no HTTP response.</summary>
    public sealed class PactmanNetworkException : PactmanException
    {
        /// <summary>Initializes the exception.</summary>
        /// <param name="message">A description of what failed to connect.</param>
        /// <param name="attempts">How many attempts were made before this error was surfaced.</param>
        /// <param name="innerException">The underlying transport failure.</param>
        public PactmanNetworkException(string message, int attempts = 1, Exception? innerException = null)
            : base(message, ErrorCategory.Network, ErrorOrigin.Local, innerException)
        {
            Attempts = attempts;
        }

        /// <summary>How many attempts were made before this error was surfaced.</summary>
        public int Attempts { get; }

        /// <inheritdoc />
        public override IReadOnlyDictionary<string, object?> ToDictionary() =>
            new FieldMap(base.ToDictionary())
            {
                ["attempts"] = Attempts,
            };
    }
}
