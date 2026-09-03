// Compiler-facing shims that let one set of sources compile against both target
// frameworks. Nothing here is API surface: every type is internal, and the net8.0
// build takes the real BCL types instead.

#if NETSTANDARD2_0

namespace System.Runtime.CompilerServices
{
    using System.ComponentModel;

    /// <summary>Enables <c>init</c> accessors on frameworks that predate them.</summary>
    [EditorBrowsable(EditorBrowsableState.Never)]
    internal static class IsExternalInit
    {
    }
}

namespace System.Diagnostics.CodeAnalysis
{
    /// <summary>Marks an output as non-null when the method returns the given value.</summary>
    [AttributeUsage(AttributeTargets.Parameter)]
    internal sealed class NotNullWhenAttribute : Attribute
    {
        /// <summary>Initializes the attribute with the return value it applies to.</summary>
        /// <param name="returnValue">The return value that guarantees a non-null output.</param>
        public NotNullWhenAttribute(bool returnValue) => ReturnValue = returnValue;

        /// <summary>The return value that guarantees a non-null output.</summary>
        public bool ReturnValue { get; }
    }
}

#endif
