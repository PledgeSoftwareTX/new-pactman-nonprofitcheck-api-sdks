using System;
using System.Collections.Generic;

namespace Pactman.NonprofitCheckPlus.Exceptions
{
    /// <summary>
    /// Base class for every exception this SDK throws.
    /// </summary>
    /// <remarks>
    /// <para>
    /// Catch this to catch everything the SDK can raise. Every subclass carries a
    /// stable <see cref="ErrorCategory"/> and an <see cref="ErrorOrigin"/>, so callers
    /// branch on the exception type or on the category — never on message text.
    /// </para>
    /// <para>
    /// API keys are never placed into an exception message, an exception property, or
    /// any <see cref="ToDictionary"/> output.
    /// </para>
    /// </remarks>
    public abstract class PactmanException : Exception
    {
        /// <summary>Initializes the exception with its category and origin.</summary>
        /// <param name="message">Human-readable description of the failure.</param>
        /// <param name="category">The stable, machine-comparable category.</param>
        /// <param name="origin">Whether the failure was raised locally or by the API.</param>
        /// <param name="innerException">The underlying failure, when there was one.</param>
        protected PactmanException(
            string message,
            ErrorCategory category,
            ErrorOrigin origin,
            Exception? innerException = null)
            : base(message, innerException)
        {
            Category = category;
            Origin = origin;
        }

        /// <summary>The stable, machine-comparable category of this failure.</summary>
        public ErrorCategory Category { get; }

        /// <summary>Whether this failure was raised locally or derived from an API response.</summary>
        public ErrorOrigin Origin { get; }

        /// <summary>
        /// A serializable view of the exception, suitable for structured logging.
        /// Never contains the API key.
        /// </summary>
        /// <returns>The exception's fields, keyed by name.</returns>
        public virtual IReadOnlyDictionary<string, object?> ToDictionary() =>
            new Dictionary<string, object?>(StringComparer.Ordinal)
            {
                ["name"] = GetType().Name,
                ["message"] = Message,
                ["category"] = Category.ToWireValue(),
                ["origin"] = Origin.ToWireValue(),
            };

        /// <summary>True when the value is any exception thrown by this SDK.</summary>
        /// <param name="value">The value to test.</param>
        /// <returns><see langword="true"/> when the value is a <see cref="PactmanException"/>.</returns>
        public static bool IsPactmanError(object? value) => value is PactmanException;
    }
}
