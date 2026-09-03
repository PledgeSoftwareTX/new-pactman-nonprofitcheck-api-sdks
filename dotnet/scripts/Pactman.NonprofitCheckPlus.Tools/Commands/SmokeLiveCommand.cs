using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text.Json;
using System.Threading.Tasks;
using Pactman.NonprofitCheckPlus.Configuration;
using Pactman.NonprofitCheckPlus.Dev;
using Pactman.NonprofitCheckPlus.Examples;
using Pactman.NonprofitCheckPlus.Exceptions;
using Pactman.NonprofitCheckPlus.Models;

namespace Pactman.NonprofitCheckPlus.Tools.Commands;

/// <summary>
/// Checks a live deployment against the two documents that describe what its responses
/// are supposed to look like.
/// </summary>
/// <remarks>
/// <para>
/// <c>response-contract.json</c> is what this package <em>promises</em>, derived from the
/// typed properties on <c>Nonprofit</c>. A failure there means the API no longer matches
/// what the SDK tells its users to expect. It is checked in and identical for everyone,
/// which is what lets these checks fail on the very first run rather than needing a
/// recording to compare against.
/// </para>
/// <para>
/// <c>response-baseline.json</c> is what production <em>returned</em>, recorded once by
/// <c>baseline-record</c> and committed. A failure there means production moved — in any
/// direction, including in the fields the contract deliberately leaves as a bare
/// <c>string</c>, where the promise is too loose to notice anything. The recording is
/// never written by a run: a baseline that rewrites itself agrees with the API by
/// construction and can never fail.
/// </para>
/// <para>No value from any response is ever printed. Exits non-zero when any check fails.</para>
/// </remarks>
internal static class SmokeLiveCommand
{
    private const int NameWidth = 14;

    private sealed record CheckResult(string Status, string Group, string Name, string Detail, string Changes);

    internal static async Task<int> RunAsync(string[] args)
    {
        var apiKey = DevEnv.Get(DevEnv.ApiKeyVariable) ?? DevEnv.Get("MOCK_API_KEY");

        if (apiKey is null)
        {
            Console.Error.WriteLine(
                $"No API key. Put {DevEnv.ApiKeyVariable} in .env, or export it, and run this again.");

            return 2;
        }

        string Redact(string value) => value.Replace(apiKey, "[redacted]", StringComparison.Ordinal);

        string ein;
        string missingEin;
        IReadOnlyList<string> bulkEins;

        try
        {
            ein = Ein.Normalize(args.Length > 0 ? args[0] : DevEnv.Ein);
            missingEin = Ein.Normalize(DevEnv.MissingEin);

            var subjects = args.Length > 1 ? args.Skip(1).ToList() : DevEnv.BulkEins.ToList();
            bulkEins = Ein.NormalizeMany(subjects.Take(DevEnv.BulkProbeLimit));
        }
        catch (PactmanException error)
        {
            Console.Error.WriteLine(error.Message);

            return 2;
        }

        using var client = new PactmanClient(new PactmanClientOptions
        {
            ApiKey = apiKey,
            BaseUrl = DevEnv.Get("PACTMAN_BASE_URL"),
            Timeout = TimeSpan.FromSeconds(20),
            Retry = new RetryOptions { MaxRetries = 2 },
        });

        Console.WriteLine($"Target        {client.BaseUrl}");
        Console.WriteLine(
            $"Subjects      {ein} · bulk {(bulkEins.Count == 0 ? "none" : string.Join(", ", bulkEins))}");
        Console.WriteLine();

        var observed = new Dictionary<string, SortedDictionary<string, string>>(StringComparer.Ordinal);
        var absent = new Dictionary<string, string>(StringComparer.Ordinal);

        try
        {
            var single = await client.Nonprofits.CheckAsync(ein);

            Console.WriteLine($"  single check   HTTP {single.Status} in {Output.Format(single.TimeTakenMs)}ms");
            observed["single"] = SignatureOf(single);
        }
        catch (PactmanException error)
        {
            absent["single"] = "the single check failed — " + Redact(error.Message);
            Console.WriteLine($"  single check   {absent["single"]}");
        }

        // The batches to try, in the order baseline-record records them.
        //
        // The partial-success batch first, because its envelope is the only one carrying
        // the item-level errors a batch with a miss comes back with; then the duplicate
        // probe, which is what a key whose bulk EINs are allowlisted falls back to — such
        // a key refuses the whole batch the moment an EIN with no record is in it.
        //
        // Sending a batch the recorder never sends would disagree with the recording on
        // batch composition alone, and report the difference as the API moving.
        var attempts = BulkAttempts(bulkEins, missingEin);

        absent["bulk"] = "no bulk subjects were given, so no bulk response was returned";

        foreach (var attempt in attempts)
        {
            try
            {
                var bulk = await client.Nonprofits.CheckBulkAsync(attempt);

                Console.WriteLine(
                    $"  bulk check     HTTP {bulk.Status}, {bulk.Organizations.Count} organization(s)");

                observed["bulk"] = SignatureOf(bulk);
                absent.Remove("bulk");

                break;
            }
            catch (PactmanException error)
            {
                absent["bulk"] = "the bulk check failed — " + Redact(error.Message);
            }
        }

        if (absent.ContainsKey("bulk"))
        {
            Console.WriteLine($"  bulk check     {absent["bulk"]}");
        }

        var contract = ReadJson(BaselinePaths.Contract);

        // The committed recording. An unreadable or absent one is a failure, not a shrug:
        // the whole point of the file is that every run is held against it, and a run that
        // silently passes for want of one is the state this replaced.
        if (!File.Exists(BaselinePaths.Baseline))
        {
            Console.Error.WriteLine(
                "\nresponse-baseline.json is missing — record it against production with "
                + "`baseline-record` and commit it.");

            return 1;
        }

        var recording = ReadJson(BaselinePaths.Baseline);
        var results = new List<CheckResult>();

        foreach (var kind in new[] { "single", "bulk" })
        {
            if (!observed.TryGetValue(kind, out var signature) || signature.Count == 0)
            {
                var reason = absent.TryGetValue(kind, out var why)
                    ? why
                    : $"the {kind} check returned no body to check";

                foreach (var name in new[] { "types", "fields", "recording" })
                {
                    results.Add(new CheckResult("skip", kind, name, reason, string.Empty));
                }

                continue;
            }

            var paths = signature.Count;
            var expected = Contract.ComposeExpected(contract, kind);

            // Values the contract permits no form of: a boolean that turned into a
            // string, a timestamp that turned ISO.
            var types = Contract.ContractDiff(expected, signature);

            results.Add(new CheckResult(
                types.Count == 0 ? "pass" : "fail",
                kind,
                "types",
                types.Count == 0
                    ? $"{paths} paths carry the predicted types and value formats"
                    : $"the live {kind} response carries values this package does not predict — "
                      + Contract.SummarizeChanges(types),
                types.Count == 0 ? string.Empty : Contract.FormatChanges(types) + ReconcileHint));

            // Fields the API sent that the package does not predict, and fields it
            // predicts that the API did not send. Both directions fail.
            var fields = Contract.CoverageDiff(expected, signature);

            results.Add(new CheckResult(
                fields.Changes.Count == 0 ? "pass" : "fail",
                kind,
                "fields",
                fields.Changes.Count == 0
                    ? $"{paths} paths, all predicted · {fields.Unreachable} predicted under a null or empty parent"
                    : $"the live {kind} response and this package disagree on which fields exist — "
                      + Contract.SummarizeChanges(fields.Changes),
                fields.Changes.Count == 0
                    ? string.Empty
                    : Contract.FormatChanges(fields.Changes) + ReconcileHint));

            // The same response, held against the committed recording of production.
            if (!recording.TryGetProperty(kind, out var recorded)
                || recorded.ValueKind != JsonValueKind.Object
                || !recorded.TryGetProperty("signature", out var recordedSignature)
                || recordedSignature.ValueKind != JsonValueKind.Object)
            {
                results.Add(new CheckResult(
                    "fail",
                    kind,
                    "recording",
                    $"no {kind} shape is recorded in response-baseline.json — record it against "
                    + "production with `baseline-record` and commit it",
                    string.Empty));

                continue;
            }

            var before = new SortedDictionary<string, string>(StringComparer.Ordinal);

            foreach (var property in recordedSignature.EnumerateObject())
            {
                before[property.Name] = property.Value.GetString()!;
            }

            // Strict in both directions on the shape, and silent on the part a recording
            // has no standing to judge: whether a nullable field happened to carry a
            // value, and the paths under a parent that arrived null. Those differ between
            // two green runs against the same unchanged deployment. The counts are
            // printed either way, so nothing is hidden.
            var baseline = Contract.BaselineDiff(before, signature);

            var recordedFrom = recording.TryGetProperty("baseUrl", out var url) ? url.GetString() : "production";
            var recordedAt = recording.TryGetProperty("recordedAt", out var at) ? at.GetString() : "an earlier date";

            results.Add(new CheckResult(
                baseline.Changes.Count == 0 ? "pass" : "fail",
                kind,
                "recording",
                baseline.Changes.Count == 0
                    ? $"{paths} paths, matching the recording · {baseline.Nullable} differ only in "
                      + $"whether a value arrived · {baseline.Unreachable} under a null or empty parent"
                    : $"the live {kind} response no longer matches the recording made from "
                      + $"{recordedFrom} on {recordedAt} — " + Contract.SummarizeChanges(baseline.Changes),
                baseline.Changes.Count == 0
                    ? string.Empty
                    : Contract.FormatChanges(baseline.Changes)
                      + "\n      if production moved and the move is intended, re-record with "
                      + "`baseline-record` and commit the diff"));
        }

        var printed = string.Empty;

        foreach (var result in results)
        {
            if (result.Group != printed)
            {
                printed = result.Group;
                Console.WriteLine($"\n{printed}  the live response against the contract and the recording");
            }

            // Padded before it is coloured: the escape sequences carry no width, and
            // padding a string that contains them pushes the column out by their length
            // on every line that has any.
            var line = result.Name.PadRight(NameWidth) + result.Detail;

            Console.WriteLine($"  {Output.Mark(result.Status)} {Colour(result.Status, line)}");

            if (result.Changes.Length > 0)
            {
                Console.WriteLine(Output.Paint(2, result.Changes));
            }
        }

        var passed = results.Count(result => result.Status == "pass");
        var failed = results.Count(result => result.Status == "fail");
        var skipped = results.Count(result => result.Status == "skip");

        Console.WriteLine("\nSummary");
        Console.WriteLine(
            $"  {results.Count} checks: {Output.Paint(32, $"{passed} passed")}, "
            + $"{(failed > 0 ? Output.Paint(31, $"{failed} failed") : "0 failed")}, {skipped} skipped");

        return failed > 0 ? 1 : 0;
    }

    private const string ReconcileHint =
        "\n      reconcile response-contract.json and Nonprofit's typed properties with the "
        + "API, once the change is understood and intended";

    private static string Colour(string status, string text) => status switch
    {
        "fail" => Output.Paint(31, text),
        "skip" => Output.Paint(2, text),
        _ => text,
    };

    /// <summary>The batches to probe, in the order the recorder records them.</summary>
    internal static IReadOnlyList<IReadOnlyList<string>> BulkAttempts(
        IReadOnlyList<string> bulkEins,
        string missingEin)
    {
        var attempts = new List<IReadOnlyList<string>>();

        if (bulkEins.Count > 0)
        {
            attempts.Add(bulkEins.Concat(new[] { missingEin }).ToList());
        }

        if (bulkEins.Count >= 2)
        {
            attempts.Add(new[] { bulkEins[1], bulkEins[0], bulkEins[1] });
        }

        return attempts;
    }

    private static SortedDictionary<string, string> SignatureOf(PactmanResult result) =>
        result.Raw.IsJson
            ? Contract.SignatureOf(result.Raw.Json!.Value)
            : new SortedDictionary<string, string>(StringComparer.Ordinal);

    private static JsonElement ReadJson(string path) =>
        JsonSerializer.Deserialize<JsonElement>(File.ReadAllText(path));
}

/// <summary>Where the contract and the recording live in the source tree.</summary>
/// <remarks>
/// Read from the working copy rather than from the resources embedded in the built
/// library, so a run reflects the files as they stand and the recorder writes the file the
/// next run reads.
/// </remarks>
internal static class BaselinePaths
{
    private static string Directory =>
        Path.Combine(DevEnv.PackageRoot(), "src", "Pactman.NonprofitCheckPlus");

    internal static string Contract => Path.Combine(Directory, "response-contract.json");

    internal static string Baseline => Path.Combine(Directory, "response-baseline.json");
}
