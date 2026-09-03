using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text.Encodings.Web;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Threading.Tasks;
using Pactman.NonprofitCheckPlus.Configuration;
using Pactman.NonprofitCheckPlus.Dev;
using Pactman.NonprofitCheckPlus.Exceptions;
using Pactman.NonprofitCheckPlus.Models;

namespace Pactman.NonprofitCheckPlus.Tools.Commands;

/// <summary>
/// Records the shape of the production API into <c>response-baseline.json</c>.
/// </summary>
/// <remarks>
/// <para>
/// <c>response-contract.json</c> says what this package <em>promises</em> a response looks
/// like. This file says what production <em>actually returned</em>, once, on a day someone
/// looked. They answer different questions and both are needed: the contract catches the
/// API drifting away from the typed model, the baseline catches the API drifting at all —
/// including in the fields the contract leaves as a bare <c>string</c>, where a promise is
/// too loose to notice anything.
/// </para>
/// <para>
/// The recording is committed, so it is the same for everyone and a change to it shows up
/// in review as what it is: production moved, and someone accepted it. That is also why
/// writing it is a deliberate command rather than something a smoke run does on the side.
/// A baseline that rewrites itself on every run agrees with the API by construction and
/// can never fail.
/// </para>
/// <para>
/// Recording spends billable checks: one single lookup and one bulk lookup against the key
/// you point it at.
/// </para>
/// </remarks>
internal static class BaselineRecordCommand
{
    private const string Note =
        "The shape production returned when this was recorded: path, JSON type and value "
        + "format, never a value. Committed, so every run of the smoke-live tool is held against "
        + "the same recording — any path added or removed, and any token that changed, fails there. "
        + "Rewrite it with `baseline-record` only when production has moved and the move is intended.";

    internal static async Task<int> RunAsync(string[] args)
    {
        var allowAnyTarget = args.Contains("--allow-any-target");
        var dryRun = args.Contains("--dry-run");

        var apiKey = DevEnv.Get(DevEnv.ApiKeyVariable);

        if (apiKey is null)
        {
            Console.Error.WriteLine(
                $"No API key. Put {DevEnv.ApiKeyVariable} in .env, or export it, and run this again.");

            return 2;
        }

        /* Replaces the credential wherever it surfaces. Applied to everything printed. */
        string Redact(string value) => value.Replace(apiKey, "[redacted]", StringComparison.Ordinal);

        var productionUrl = PactmanEnvironments.Default.BaseUrl();
        var baseUrl = DevEnv.Get("PACTMAN_BASE_URL") ?? productionUrl;

        // The baseline every run is held against has to come from the deployment those
        // runs are about. A recording made against a sandbox would quietly turn the
        // sandbox into the standard, and nothing downstream could tell.
        if (!Normalize(baseUrl).Equals(Normalize(productionUrl), StringComparison.Ordinal) && !allowAnyTarget)
        {
            Console.Error.WriteLine(
                $"Refusing to record from {baseUrl}.\n"
                + $"The committed baseline describes production ({productionUrl}); recording it from "
                + "anywhere else makes that deployment the standard for everyone.\n"
                + "Unset PACTMAN_BASE_URL, or pass --allow-any-target if you mean it.");

            return 2;
        }

        string ein;
        string missingEin;
        IReadOnlyList<string> bulkEins;

        try
        {
            ein = Ein.Normalize(DevEnv.Ein);
            missingEin = Ein.Normalize(DevEnv.MissingEin);

            // The same batch smoke-live sends, so the two signatures describe the same
            // set of organizations rather than differing by batch size.
            bulkEins = Ein.NormalizeMany(DevEnv.BulkEins.Take(DevEnv.BulkProbeLimit));
        }
        catch (PactmanException error)
        {
            Console.Error.WriteLine(error.Message);

            return 2;
        }

        using var client = new PactmanClient(new PactmanClientOptions
        {
            ApiKey = apiKey,
            BaseUrl = baseUrl,
            Timeout = TimeSpan.FromSeconds(20),
            Retry = new RetryOptions { MaxRetries = 2 },
        });

        var attempts = SmokeLiveCommand.BulkAttempts(bulkEins, missingEin);

        Console.WriteLine(Redact($"Target        {baseUrl}"));
        Console.WriteLine(Redact(
            $"Subjects      {ein} · bulk {(bulkEins.Count == 0 ? "none" : string.Join(", ", bulkEins))}"));
        Console.WriteLine($"Cost          up to {1 + attempts.Count} billable request(s)");
        Console.WriteLine();

        var single = await RecordAsync("single", () => client.Nonprofits.CheckAsync(ein), Redact)
            .ConfigureAwait(false);

        SortedDictionary<string, string>? bulk = null;

        foreach (var attempt in attempts)
        {
            bulk = await RecordAsync("bulk", () => client.Nonprofits.CheckBulkAsync(attempt), Redact)
                .ConfigureAwait(false);

            if (bulk is not null)
            {
                break;
            }
        }

        if (single is null && bulk is null)
        {
            Console.Error.WriteLine("\nNothing was recorded. The baseline on disk is unchanged.");

            return 1;
        }

        // A half that could not be recorded keeps whatever is already on disk.
        //
        // A key whose allowlist refuses the batch, or a lookup that timed out, is a reason
        // to record nothing new — not a reason to throw away a good recording made on a
        // day the call worked. Overwriting it with null would delete the standard the bulk
        // checks are held against, and the run that noticed would be the one that stopped
        // failing.
        JsonNode? existing = File.Exists(BaselinePaths.Baseline)
            ? JsonNode.Parse(File.ReadAllText(BaselinePaths.Baseline))
            : null;

        var kept = new List<string>();

        JsonNode? Half(string kind, SortedDictionary<string, string>? recorded)
        {
            if (recorded is not null)
            {
                var signature = new JsonObject();

                foreach (var entry in recorded)
                {
                    signature[entry.Key] = entry.Value;
                }

                return new JsonObject { ["signature"] = signature };
            }

            var stored = existing?[kind];

            if (stored?["signature"] is not null)
            {
                kept.Add(kind);
            }

            return stored?.DeepClone();
        }

        var baseline = new JsonObject
        {
            ["note"] = Note,
            ["recordedAt"] = DateTime.UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ", CultureInfo.InvariantCulture),
            ["baseUrl"] = baseUrl,
            ["sdkVersion"] = SdkVersion.Version,
            ["single"] = Half("single", single),
            ["bulk"] = Half("bulk", bulk),
        };

        if (dryRun)
        {
            Console.WriteLine("\n--dry-run: nothing written.");

            return 0;
        }

        File.WriteAllText(
            BaselinePaths.Baseline,
            baseline.ToJsonString(new JsonSerializerOptions
            {
                WriteIndented = true,
                Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping,
            }) + "\n");

        Console.WriteLine(Redact(
            $"\nWrote response-baseline.json — recorded from {baseUrl} on SDK {SdkVersion.Version}."));

        if (kept.Count > 0)
        {
            Console.WriteLine(
                $"The {string.Join(" and ", kept)} half was left as it was — this run could not record it.");
        }

        Console.WriteLine("Commit it. Every smoke run from now on is held against it.");

        return 0;
    }

    /// <summary>Runs one lookup and reduces it to a signature, or reports why it could not.</summary>
    private static async Task<SortedDictionary<string, string>?> RecordAsync<T>(
        string label,
        Func<Task<T>> call,
        Func<string, string> redact)
        where T : PactmanResult
    {
        T result;

        try
        {
            result = await call().ConfigureAwait(false);
        }
        catch (Exception error)
        {
            Console.WriteLine(redact($"  {label,-8} failed — {error.Message}"));

            return null;
        }

        // A non-JSON body leaves the raw text in place rather than an envelope, and there
        // is no shape in a string to record.
        if (!result.Raw.IsJson)
        {
            Console.WriteLine($"  {label,-8} no response body to record");

            return null;
        }

        var signature = Contract.SignatureOf(result.Raw.Json!.Value);

        Console.WriteLine($"  {label,-8} {signature.Count} paths");

        return signature;
    }

    private static string Normalize(string url) => url.TrimEnd('/').ToLowerInvariant();
}
