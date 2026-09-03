namespace Pactman.NonprofitCheckPlus.Exceptions
{
    /// <summary>HTTP 400. The API rejected the request as malformed.</summary>
    public sealed class PactmanBadRequestException : PactmanApiException
    {
        /// <summary>Initializes the exception from response metadata.</summary>
        /// <param name="message">Human-readable description of the failure.</param>
        /// <param name="init">The metadata the transport collected from the response.</param>
        public PactmanBadRequestException(string message, ApiErrorInit init)
            : base(message, init, ErrorCategory.BadRequest)
        {
        }
    }
}
