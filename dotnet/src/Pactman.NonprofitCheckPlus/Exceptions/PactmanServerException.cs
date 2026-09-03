namespace Pactman.NonprofitCheckPlus.Exceptions
{
    /// <summary>HTTP 5xx. The API failed to process the request.</summary>
    public sealed class PactmanServerException : PactmanApiException
    {
        /// <summary>Initializes the exception from response metadata.</summary>
        /// <param name="message">Human-readable description of the failure.</param>
        /// <param name="init">The metadata the transport collected from the response.</param>
        public PactmanServerException(string message, ApiErrorInit init)
            : base(message, init, ErrorCategory.Server)
        {
        }
    }
}
