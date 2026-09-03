namespace Pactman.NonprofitCheckPlus.Exceptions
{
    /// <summary>HTTP 401. The API key is missing, malformed, revoked or unrecognized.</summary>
    public sealed class PactmanAuthenticationException : PactmanApiException
    {
        /// <summary>Initializes the exception from response metadata.</summary>
        /// <param name="message">Human-readable description of the failure.</param>
        /// <param name="init">The metadata the transport collected from the response.</param>
        public PactmanAuthenticationException(string message, ApiErrorInit init)
            : base(message, init, ErrorCategory.Authentication)
        {
        }
    }
}
