namespace Pactman.NonprofitCheckPlus
{
    /// <summary>
    /// The SDK version, reported in the <c>User-Agent</c> header.
    /// </summary>
    /// <remarks>
    /// Kept in sync with the <c>PactmanSdkVersion</c> property in
    /// <c>Directory.Build.props</c> by a unit test rather than a build step, so the
    /// value is a compile-time constant instead of an assembly-metadata lookup at
    /// runtime.
    /// </remarks>
    public static class SdkVersion
    {
        /// <summary>The release version, reported in the <c>User-Agent</c> header.</summary>
        public const string Version = "1.0.0";

        /// <summary>The NuGet package identifier, reported in the <c>User-Agent</c> header.</summary>
        public const string PackageName = "Pactman.NonprofitCheckPlus";
    }
}
