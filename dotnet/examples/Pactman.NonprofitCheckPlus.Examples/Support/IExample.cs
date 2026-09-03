using System.Threading.Tasks;

namespace Pactman.NonprofitCheckPlus.Examples;

/// <summary>One runnable example.</summary>
/// <remarks>
/// Every example is discovered by reflection, so adding a class that implements this is
/// all it takes for the runner and the CI smoke pass to pick it up.
/// </remarks>
public interface IExample
{
    /// <summary>The example's identifier, such as <c>ex-01</c>.</summary>
    string Id { get; }

    /// <summary>A one-line title, shown by <c>--list</c>.</summary>
    string Title { get; }

    /// <summary>Runs the example.</summary>
    /// <param name="args">Arguments after the example id, such as an EIN to look up.</param>
    Task RunAsync(string[] args);
}

/// <summary>An example that ran but did not get the outcome it was demonstrating.</summary>
/// <remarks>
/// Examples are run in-process by the smoke runner, so an example that has failed says so
/// by throwing rather than by exiting the process out from under everything after it.
/// </remarks>
public sealed class ExampleFailedException : System.Exception
{
    /// <summary>Initializes the exception.</summary>
    /// <param name="message">What the example expected, and what it saw instead.</param>
    public ExampleFailedException(string message)
        : base(message)
    {
    }
}
