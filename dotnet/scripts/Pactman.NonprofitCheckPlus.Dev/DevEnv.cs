using System;
using System.Collections.Generic;
using System.IO;
using System.Text.RegularExpressions;

namespace Pactman.NonprofitCheckPlus.Dev;

/// <summary>
/// The <c>.env</c> beside the package, and the organizations every live script reads.
/// </summary>
/// <remarks>
/// Kept here rather than in one script so <c>smoke-live</c> and <c>baseline-record</c>
/// read the same file the same way and talk about the same subjects. The two have to
/// agree on which deployment and which organizations they are describing — a signature
/// collapses every element of <c>data[]</c> onto one path, so a recording made from one
/// batch and a run made from another disagree wherever the two sets of organizations
/// differ. A second copy of this parser, or a second list of EINs, is how they would stop
/// agreeing.
/// </remarks>
public static class DevEnv
{
    /// <summary>The variable the credential is read from, in the environment or in <c>.env</c>.</summary>
    public const string ApiKeyVariable = "PACTMAN_API_KEY";

    /// <summary>
    /// The primary organization these scripts check.
    /// </summary>
    /// <remarks>
    /// A primary subject with a record, a second one to give the bulk order and duplicate
    /// probes something to work with, and a well-formed EIN with no record for the
    /// not-found and partial-success paths. The first two are reachable on a free-tier
    /// key, so a free key gets as far as a free key can.
    /// <para>
    /// These are also the subjects <c>response-baseline.json</c> describes. Changing one
    /// means re-recording it.
    /// </para>
    /// </remarks>
    public const string Ein = "996589560";

    /// <summary>The organizations the bulk probes send.</summary>
    public static IReadOnlyList<string> BulkEins { get; } = new[] { "996589560", "996202676" };

    /// <summary>A well-formed EIN with no record, for the not-found paths.</summary>
    public const string MissingEin = "999999999";

    /// <summary>
    /// How many of the bulk subjects a run actually sends.
    /// </summary>
    /// <remarks>
    /// The bulk probes read the first few and the rest would cost quota unspent — but the
    /// recorder has to send the same batch the smoke run does. Same number, same subjects,
    /// or the comparison reports the batch size as drift.
    /// </remarks>
    public const int BulkProbeLimit = 3;

    /// <summary>Assignment lines a <c>.env</c> is allowed to carry, <c>export</c> prefix included.</summary>
    private static readonly Regex Assignment = new(@"^\s*(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)$");

    /// <summary>What <see cref="LoadEnvFile"/> found.</summary>
    /// <param name="Path">The file that was read.</param>
    /// <param name="Names">The variables it set.</param>
    public sealed record EnvFile(string Path, IReadOnlyList<string> Names);

    /// <summary>
    /// Loads the <c>.env</c> beside the package, so the key and any standing overrides live
    /// in a file rather than in the shell for every run. The file is gitignored.
    /// </summary>
    /// <remarks>
    /// A variable already in the environment wins: exporting one for a single run must not
    /// be silently overridden by a file someone set up months ago.
    /// </remarks>
    /// <param name="path">The file to read, or <see langword="null"/> for the default location.</param>
    /// <returns>What was loaded, or <see langword="null"/> when there was no file.</returns>
    public static EnvFile? LoadEnvFile(string? path = null)
    {
        path ??= Path.Combine(PackageRoot(), ".env");

        if (!File.Exists(path))
        {
            return null;
        }

        string contents;

        try
        {
            contents = File.ReadAllText(path);
        }
        catch (IOException)
        {
            return null;
        }

        var names = new List<string>();

        // Both line endings: a .env saved on Windows ends its lines with CRLF, and a
        // trailing CR left on the value would become part of it.
        foreach (var line in contents.Split('\n'))
        {
            var matched = Assignment.Match(line.TrimEnd('\r'));

            if (!matched.Success)
            {
                continue;
            }

            var name = matched.Groups[1].Value;

            if (Get(name) is not null)
            {
                continue;
            }

            var value = matched.Groups[2].Value.Trim();

            // A quoted value keeps its inner whitespace; the quotes are syntax.
            if (value.Length >= 2 && value[0] == value[^1] && (value[0] == '"' || value[0] == '\''))
            {
                value = value[1..^1];
            }

            Environment.SetEnvironmentVariable(name, value);
            names.Add(name);
        }

        return new EnvFile(path, names);
    }

    /// <summary>
    /// One environment variable, or <see langword="null"/> when it is unset or empty.
    /// </summary>
    /// <remarks>A variable that is present but empty is not a value. Both are nothing here.</remarks>
    /// <param name="name">The variable to read.</param>
    /// <returns>The value, or <see langword="null"/>.</returns>
    public static string? Get(string name)
    {
        var value = Environment.GetEnvironmentVariable(name);

        return string.IsNullOrWhiteSpace(value) ? null : value;
    }

    /// <summary>
    /// The <c>dotnet/</c> directory, found by walking up from wherever the tool was built to.
    /// </summary>
    /// <returns>The package root, or the current directory when it cannot be found.</returns>
    public static string PackageRoot()
    {
        var directory = new DirectoryInfo(AppContext.BaseDirectory);

        while (directory is not null)
        {
            if (File.Exists(Path.Combine(directory.FullName, "Directory.Build.props")))
            {
                return directory.FullName;
            }

            directory = directory.Parent;
        }

        return Directory.GetCurrentDirectory();
    }
}
