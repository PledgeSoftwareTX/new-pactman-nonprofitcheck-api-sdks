using System;

namespace Pactman.NonprofitCheckPlus.Exceptions
{
    /// <summary>Whether an error was raised locally or derived from an API response.</summary>
    public enum ErrorOrigin
    {
        /// <summary>Raised by this SDK before, or instead of, an HTTP response.</summary>
        Local = 0,

        /// <summary>Derived from a response the Pactman API returned.</summary>
        Api = 1,
    }

    /// <summary>Wire spellings for <see cref="ErrorOrigin"/>.</summary>
    public static class ErrorOrigins
    {
        /// <summary>The origin's wire value.</summary>
        /// <param name="origin">The origin to spell.</param>
        /// <returns>The canonical lower-case name.</returns>
        /// <exception cref="ArgumentOutOfRangeException">The value is not a declared origin.</exception>
        public static string ToWireValue(this ErrorOrigin origin) => origin switch
        {
            ErrorOrigin.Local => "local",
            ErrorOrigin.Api => "api",
            _ => throw new ArgumentOutOfRangeException(nameof(origin), origin, "Unknown error origin."),
        };
    }
}
