namespace Pactman.NonprofitCheckPlus.Exceptions
{
    /// <summary>HTTP 403. The key is valid but lacks access to the resource.</summary>
    public sealed class PactmanAuthorizationException : PactmanApiException
    {
        /// <summary>Initializes the exception from response metadata.</summary>
        /// <param name="message">Human-readable description of the failure.</param>
        /// <param name="init">The metadata the transport collected from the response.</param>
        public PactmanAuthorizationException(string message, ApiErrorInit init)
            : base(message, init, ErrorCategory.Authorization)
        {
        }
    }
}
