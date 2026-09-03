namespace Pactman.NonprofitCheckPlus.Exceptions
{
    /// <summary>
    /// HTTP 429. <see cref="PactmanApiException.RetryAfter"/> carries the server's
    /// <c>Retry-After</c> when it sent one.
    /// </summary>
    public sealed class PactmanRateLimitException : PactmanApiException
    {
        /// <summary>Initializes the exception from response metadata.</summary>
        /// <param name="message">Human-readable description of the failure.</param>
        /// <param name="init">The metadata the transport collected from the response.</param>
        public PactmanRateLimitException(string message, ApiErrorInit init)
            : base(message, init, ErrorCategory.RateLimit)
        {
        }
    }
}
