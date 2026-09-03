using Pactman.NonprofitCheckPlus.Models;

namespace Pactman.NonprofitCheckPlus.Http
{
    /// <summary>A parsed HTTP response plus the metadata callers need.</summary>
    internal sealed class TransportResponse
    {
        /// <summary>Initializes the response.</summary>
        /// <param name="status">HTTP status of the response.</param>
        /// <param name="requestId">Correlation identifier from the headers, when present.</param>
        /// <param name="body">The decoded envelope, or the raw text when it was not JSON.</param>
        /// <param name="attempts">How many attempts were made.</param>
        internal TransportResponse(int status, string? requestId, ResponseBody body, int attempts)
        {
            Status = status;
            RequestId = requestId;
            Body = body;
            Attempts = attempts;
        }

        /// <summary>HTTP status of the response.</summary>
        internal int Status { get; }

        /// <summary>Correlation identifier from the headers, when present.</summary>
        internal string? RequestId { get; }

        /// <summary>The decoded envelope, or the raw text when it was not JSON.</summary>
        internal ResponseBody Body { get; }

        /// <summary>How many attempts were made.</summary>
        internal int Attempts { get; }
    }
}
