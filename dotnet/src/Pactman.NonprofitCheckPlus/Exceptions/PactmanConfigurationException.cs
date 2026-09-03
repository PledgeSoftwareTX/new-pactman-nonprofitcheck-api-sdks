namespace Pactman.NonprofitCheckPlus.Exceptions
{
    /// <summary>
    /// The client options were unusable — a missing API key, a malformed base URL.
    /// </summary>
    public sealed class PactmanConfigurationException : PactmanException
    {
        /// <summary>Initializes the exception.</summary>
        /// <param name="message">What was wrong with the options, and how to fix it.</param>
        public PactmanConfigurationException(string message)
            : base(message, ErrorCategory.Configuration, ErrorOrigin.Local)
        {
        }
    }
}
