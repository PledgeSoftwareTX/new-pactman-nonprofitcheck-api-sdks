namespace Pactman.NonprofitCheckPlus.Configuration
{
    /// <summary>Per-request overrides for a bulk check.</summary>
    public sealed class BulkRequestOptions : RequestOptions
    {
        /// <summary>
        /// Remove duplicate EINs before sending, keeping first-seen order.
        /// </summary>
        /// <remarks>
        /// Off by default: duplicates are sent exactly as supplied, because each one
        /// consumes quota and silently dropping them would misreport what was checked.
        /// </remarks>
        public bool Dedupe { get; set; }
    }
}
