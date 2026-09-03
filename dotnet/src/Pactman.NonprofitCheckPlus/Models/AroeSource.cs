using System.Collections.Generic;
using System.Text.Json;

namespace Pactman.NonprofitCheckPlus.Models
{
    /// <summary>IRS Automatic Revocation of Exemption findings.</summary>
    public sealed class AroeSource : SourceView
    {
        /// <summary>Initializes the view over the projected fields.</summary>
        /// <param name="fields">The fields copied from the organization.</param>
        public AroeSource(IEnumerable<KeyValuePair<string, JsonElement>> fields)
            : base(fields)
        {
        }

        /// <summary>The IRS automatic revocation code, when the exemption was revoked.</summary>
        public string? RevocationCode => GetString("revocation_code");

        /// <summary>The date the exemption was automatically revoked.</summary>
        public string? RevocationDate => GetString("revocation_date");

        /// <summary>The date the exemption was reinstated, when it was.</summary>
        public string? ReinstatementDate => GetString("reinstatement_date");
    }
}
