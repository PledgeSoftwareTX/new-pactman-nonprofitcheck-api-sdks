namespace Pactman.NonprofitCheckPlus.Exceptions
{
    /// <summary>HTTP 404. No matching record.</summary>
    public sealed class PactmanNotFoundException : PactmanApiException
    {
        /// <summary>Initializes the exception from response metadata.</summary>
        /// <param name="message">Human-readable description of the failure.</param>
        /// <param name="init">The metadata the transport collected from the response.</param>
        public PactmanNotFoundException(string message, ApiErrorInit init)
            : base(message, init, ErrorCategory.NotFound)
        {
        }
    }
}
