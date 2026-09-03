using System;
using System.Collections.Generic;

namespace Pactman.NonprofitCheckPlus
{
    /// <summary>
    /// Named Pactman environments that are supported for public SDK use.
    /// </summary>
    /// <remarks>
    /// <para>
    /// Endpoint hosts are declared here and nowhere else. Nothing else in this
    /// package contains a literal Pactman host.
    /// </para>
    /// <para>
    /// Pactman's QA, SIT and sandbox hosts are internal and are deliberately not
    /// exposed. Point at one with <see cref="Configuration.PactmanClientOptions.BaseUrl"/> if you
    /// have been given access to it.
    /// </para>
    /// </remarks>
    public enum PactmanEnvironment
    {
        /// <summary>The Pactman production API.</summary>
        Production = 0,
    }

    /// <summary>Base URLs and name parsing for <see cref="PactmanEnvironment"/>.</summary>
    public static class PactmanEnvironments
    {
        /// <summary>The environment used when none is supplied.</summary>
        public const PactmanEnvironment Default = PactmanEnvironment.Production;

        /// <summary>The base URL every request in an environment is sent to.</summary>
        /// <param name="environment">The environment to resolve.</param>
        /// <returns>The absolute base URL, with no trailing slash.</returns>
        /// <exception cref="ArgumentOutOfRangeException">The value is not a declared environment.</exception>
        public static string BaseUrl(this PactmanEnvironment environment) => environment switch
        {
            PactmanEnvironment.Production => "https://entities.pactman.org",
            _ => throw new ArgumentOutOfRangeException(nameof(environment), environment, "Unknown Pactman environment."),
        };

        /// <summary>The lower-case wire name of an environment, as the other Pactman SDKs spell it.</summary>
        /// <param name="environment">The environment to name.</param>
        /// <returns>The environment's canonical name.</returns>
        /// <exception cref="ArgumentOutOfRangeException">The value is not a declared environment.</exception>
        public static string Name(this PactmanEnvironment environment) => environment switch
        {
            PactmanEnvironment.Production => "production",
            _ => throw new ArgumentOutOfRangeException(nameof(environment), environment, "Unknown Pactman environment."),
        };

        /// <summary>Every environment name the SDK understands.</summary>
        /// <returns>The supported environments, in declaration order.</returns>
        public static IReadOnlyList<PactmanEnvironment> Supported() => new[] { PactmanEnvironment.Production };

        /// <summary>The supported names, joined for an error message.</summary>
        /// <returns>A comma-separated list of environment names.</returns>
        public static string SupportedNames() => string.Join(", ", Array.ConvertAll(new[] { PactmanEnvironment.Production }, Name));

        /// <summary>
        /// Parses an environment name, case-insensitively.
        /// </summary>
        /// <param name="name">The name to parse, such as <c>production</c>.</param>
        /// <param name="environment">The parsed environment when this returns <see langword="true"/>.</param>
        /// <returns><see langword="true"/> when the name is a supported environment.</returns>
        public static bool TryParse(string? name, out PactmanEnvironment environment)
        {
            environment = Default;

            if (string.IsNullOrWhiteSpace(name))
            {
                return false;
            }

            if (string.Equals(name!.Trim(), "production", StringComparison.OrdinalIgnoreCase))
            {
                environment = PactmanEnvironment.Production;
                return true;
            }

            return false;
        }
    }
}
