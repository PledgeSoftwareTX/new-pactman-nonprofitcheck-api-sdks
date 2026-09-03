namespace Pactman.NonprofitCheckPlus
{
    /// <summary>The API surface this SDK wraps, declared once.</summary>
    public static class Endpoints
    {
        /// <summary>
        /// Path of the single-check endpoint. <c>{ein}</c> is replaced with a normalized EIN.
        /// </summary>
        public const string SingleCheckPath = "/api/entities/nonprofitcheck/v1/us/ein/{ein}";

        /// <summary>Path of the bulk-check endpoint.</summary>
        public const string BulkCheckPath = "/api/entities/nonprofitcheckbulk/v1/us/eins";

        /// <summary>
        /// Maximum number of EINs the API accepts in one bulk request.
        /// </summary>
        /// <remarks>This mirrors the server-side limit. It is declared once, here.</remarks>
        public const int MaxBulkEins = 50;
    }
}
