using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace Pactman.NonprofitCheckPlus.Dev;

/// <summary>
/// Signatures of a JSON response, and the differences between two of them.
/// </summary>
/// <remarks>
/// <para>
/// A recorded copy of a live response is worthless as a drift detector: every run
/// returns a fresh <c>report_date</c>, a different <c>timeTaken</c> and a usage counter
/// that only goes up, so a byte comparison fails for reasons that have nothing to do
/// with the API changing. What is stable is the shape — which fields exist, what type
/// each carries, and what form its values take. That is what a signature captures, and
/// comparing one against a recorded baseline is how <c>smoke-live</c> answers "has the
/// API changed?" without re-recording every time the IRS data behind an organization is
/// refreshed.
/// </para>
/// <para>
/// A signature is a flat, sorted map of path to type token:
/// </para>
/// <code>
/// code                                                  number
/// data.ein                                              digits:9
/// data.most_recent_bmf                                  date
/// data.organization_types[].deductibility_limitation    text
/// data.pub78_verified                                   boolean
/// data.revocation_code                                  null
/// errors                                                null
/// </code>
/// <para>
/// Flat, so a field that appears, disappears or changes type is one line in a git diff,
/// and so comparing two signatures is a key-by-key walk rather than a recursive descent
/// that has to re-derive structure it already knows.
/// </para>
/// <para>
/// The two halves are compared separately — <see cref="SchemaDiff"/> over the paths,
/// <see cref="TypeDiff"/> over the tokens — because they fail for different reasons and
/// mean different things. A field that disappeared breaks callers that read it; a field
/// that changed type breaks callers that parse it. Reporting them as one number would
/// say only that something moved.
/// </para>
/// <para>Tokens:</para>
/// <code>
/// object, array, boolean, number, null   the JSON type, structural
/// date          M/D/YYYY h:mm:ss AM — the format every API timestamp uses
/// date:iso      an ISO-8601 timestamp, which this API does not currently send
/// digits:9      a string of digits, grouped by length: "411787097" is
///               digits:9, "01085-2643" is digits:5-4, "00" is digits:2
/// url           an http(s) URL
/// ofac-sentence the SDN sentence ofac_status carries, in either wording
/// empty         an empty or whitespace-only string
/// text          any other string
/// </code>
/// <para>
/// A path that carries more than one token across a single response — a field that is a
/// date on one organization in a bulk batch and null on another — records them sorted
/// and joined by "|", as in <c>date|null</c>.
/// </para>
/// <para>
/// Only shapes go in. No value from the response is ever recorded, so a baseline is safe
/// to commit and a diff is safe to print.
/// </para>
/// </remarks>
public static class Contract
{
    /// <summary>The format every timestamp in this API uses. See <see cref="Fixtures.ApiDate"/>.</summary>
    private static readonly Regex ApiDatePattern =
        new(@"^\d{1,2}/\d{1,2}/\d{4},? \d{1,2}:\d{2}:\d{2} ?(?:AM|PM)$", RegexOptions.IgnoreCase);

    private static readonly Regex IsoDatePattern = new(@"^\d{4}-\d{2}-\d{2}(?:[T ]\d{2}:\d{2}|$)");

    /// <summary>Digits, optionally in hyphen-separated groups: EINs, ZIPs, IRS codes.</summary>
    private static readonly Regex DigitGroupsPattern = new(@"^\d+(?:-\d+)*$");

    private static readonly Regex UrlLikePattern = new(@"^https?://", RegexOptions.IgnoreCase);

    /// <summary>
    /// The clause both OFAC wordings share.
    /// </summary>
    /// <remarks>
    /// Matching the clause rather than either whole sentence keeps a genuine change of
    /// wording visible — it would fall back to <c>text</c> — while a subject that goes
    /// from "was NOT included" to "may be included", or a possible match whose UID
    /// differs, stays the same shape. That is a change in the data, not the contract.
    /// </remarks>
    private static readonly Regex OfacSentencePattern =
        new(@"Specially Designated Nationals ?\(SDN\) list", RegexOptions.IgnoreCase);

    private static readonly string[] StringTokens =
        { "text", "empty", "date", "date:iso", "url", "ofac-sentence" };

    /// <summary>Classifies a string by the form of its value, never by the value itself.</summary>
    public static string FormatOf(string value)
    {
        // Newer runtimes format times with a narrow no-break space; the API sends a
        // plain one. Normalize so the same timestamp is not two different tokens.
        var text = value.Replace('\u202F', ' ').Replace('\u00A0', ' ');

        if (string.IsNullOrWhiteSpace(text))
        {
            return "empty";
        }

        if (ApiDatePattern.IsMatch(text))
        {
            return "date";
        }

        if (IsoDatePattern.IsMatch(text))
        {
            return "date:iso";
        }

        if (DigitGroupsPattern.IsMatch(text))
        {
            return "digits:" + string.Join("-", text.Split('-').Select(group => group.Length));
        }

        if (UrlLikePattern.IsMatch(text))
        {
            return "url";
        }

        return OfacSentencePattern.IsMatch(text) ? "ofac-sentence" : "text";
    }

    /// <summary>Builds the signature of a decoded JSON response.</summary>
    public static SortedDictionary<string, string> SignatureOf(JsonElement value)
    {
        var tokens = new SortedDictionary<string, SortedSet<string>>(StringComparer.Ordinal);
        Collect(value, string.Empty, tokens);

        var signature = new SortedDictionary<string, string>(StringComparer.Ordinal);

        foreach (var entry in tokens)
        {
            signature[entry.Key] = string.Join("|", entry.Value);
        }

        return signature;
    }

    /// <summary>
    /// Fields the API stopped sending, and fields it started sending.
    /// </summary>
    /// <remarks>
    /// Additions count. A field the API added is forward-compatible for a caller — the
    /// SDK surfaces it through <c>Get()</c> either way — but it is still the API
    /// changing, and a baseline that quietly absorbs additions cannot tell you when it did.
    /// </remarks>
    public static IReadOnlyList<Change> SchemaDiff(
        IReadOnlyDictionary<string, string> baseline,
        IReadOnlyDictionary<string, string> current)
    {
        var changes = new List<Change>();

        foreach (var entry in baseline)
        {
            if (!current.ContainsKey(entry.Key))
            {
                changes.Add(new Change("removed", entry.Key, Token: entry.Value));
            }
        }

        foreach (var entry in current)
        {
            if (!baseline.ContainsKey(entry.Key))
            {
                changes.Add(new Change("added", entry.Key, Token: entry.Value));
            }
        }

        return Sort(changes);
    }

    /// <summary>
    /// Fields whose type or value format changed, across the paths both signatures have.
    /// </summary>
    /// <remarks>
    /// Paths only one of them has are <see cref="SchemaDiff"/>'s to report, so a single
    /// renamed field is one failure rather than two.
    /// </remarks>
    public static IReadOnlyList<Change> TypeDiff(
        IReadOnlyDictionary<string, string> baseline,
        IReadOnlyDictionary<string, string> current)
    {
        var changes = new List<Change>();

        foreach (var entry in baseline)
        {
            if (current.TryGetValue(entry.Key, out var token) && token != entry.Value)
            {
                changes.Add(new Change("changed", entry.Key, From: entry.Value, To: token));
            }
        }

        return Sort(changes);
    }

    /// <summary>
    /// True when an observed token is permitted by a declared shape.
    /// </summary>
    /// <remarks>
    /// <c>response-contract.json</c> declares each field as the tokens it may carry,
    /// joined by "|" — <c>"digits:9|null"</c>, <c>"boolean|null"</c>. It also uses
    /// <c>string</c> as a wildcard over every string form, for the fields where the SDK
    /// promises "some text" rather than a particular shape. That is the one looseness in
    /// the vocabulary, and it is deliberate: declaring <c>organization_name</c> as
    /// <c>text</c> would fail the day an organization's name is all digits.
    /// </remarks>
    public static bool Satisfies(string declared, string observed) =>
        observed.Split('|').All(token => Permits(declared, token));

    /// <summary>
    /// Whether one observed token is one a declared shape allows.
    /// </summary>
    /// <remarks>
    /// <see cref="Satisfies"/> asks the same question of a whole observed token string;
    /// this is the single-token form, which is what <see cref="ContractDiff"/> needs to
    /// name the tokens that offend rather than only that one did.
    /// </remarks>
    public static bool Permits(string allowed, string token)
    {
        var permitted = allowed.Split('|');

        return permitted.Contains(token, StringComparer.Ordinal)
            || (permitted.Contains("string", StringComparer.Ordinal) && IsStringToken(token));
    }

    /// <summary>"2 removed, 1 added" — the counts that are not zero.</summary>
    public static string SummarizeChanges(IReadOnlyList<Change> changes)
    {
        var parts = new List<string>();

        foreach (var kind in new[] { "removed", "changed", "added" })
        {
            var count = changes.Count(change => change.Kind == kind);

            if (count > 0)
            {
                parts.Add($"{count} {kind}");
            }
        }

        return parts.Count == 0 ? "no differences" : string.Join(", ", parts);
    }

    /// <summary>
    /// One line per change, indented to sit under the line it explains.
    /// </summary>
    /// <remarks>
    /// Every change, with nothing elided. A run that says a field moved and then hides
    /// which one sends you back to the deployment to find out by hand, and the list is
    /// only long when something large moved — which is exactly when the whole of it is
    /// what you need.
    /// </remarks>
    public static string FormatChanges(IReadOnlyList<Change> changes, string indent = "      ") =>
        string.Join("\n", changes.Select(change => indent + change));

    private static bool IsStringToken(string token) =>
        StringTokens.Contains(token, StringComparer.Ordinal) || token.StartsWith("digits:", StringComparison.Ordinal);

    private static string TokenFor(JsonElement value) => value.ValueKind switch
    {
        JsonValueKind.Null or JsonValueKind.Undefined => "null",
        JsonValueKind.Array => "array",
        JsonValueKind.Object => "object",
        JsonValueKind.String => FormatOf(value.GetString() ?? string.Empty),
        JsonValueKind.True or JsonValueKind.False => "boolean",
        JsonValueKind.Number => "number",
        _ => "unknown",
    };

    private static void Collect(
        JsonElement value,
        string path,
        SortedDictionary<string, SortedSet<string>> tokens)
    {
        if (path.Length > 0)
        {
            if (!tokens.TryGetValue(path, out var set))
            {
                set = new SortedSet<string>(StringComparer.Ordinal);
                tokens[path] = set;
            }

            set.Add(TokenFor(value));
        }

        // Every element of a list contributes to one path, so a batch of ten
        // organizations describes one record shape rather than ten.
        if (value.ValueKind == JsonValueKind.Array)
        {
            foreach (var item in value.EnumerateArray())
            {
                Collect(item, path + "[]", tokens);
            }

            return;
        }

        if (value.ValueKind == JsonValueKind.Object)
        {
            foreach (var property in value.EnumerateObject())
            {
                Collect(property.Value, path.Length == 0 ? property.Name : $"{path}.{property.Name}", tokens);
            }
        }
    }

    private static IReadOnlyList<Change> Sort(List<Change> changes)
    {
        changes.Sort((left, right) =>
        {
            var byRank = left.Rank.CompareTo(right.Rank);

            return byRank != 0 ? byRank : string.CompareOrdinal(left.Path, right.Path);
        });

        return changes;
    }

    /// <summary>
    /// Every enclosing path of a signature path, innermost first.
    /// </summary>
    /// <remarks>
    /// <c>data.organization_types[].organization_type</c> yields
    /// <c>data.organization_types[]</c>, <c>data.organization_types</c>, <c>data</c>.
    /// </remarks>
    private static IReadOnlyList<string> AncestorsOf(string path)
    {
        var ancestors = new List<string>();
        var rest = path;

        while (true)
        {
            if (rest.EndsWith("[]", StringComparison.Ordinal))
            {
                rest = rest.Substring(0, rest.Length - 2);
            }
            else
            {
                var dot = rest.LastIndexOf('.');

                if (dot < 0)
                {
                    return ancestors;
                }

                rest = rest.Substring(0, dot);
            }

            ancestors.Add(rest);
        }
    }

    /// <summary>
    /// Whether a container above this path arrived in a form with no room for it.
    /// </summary>
    /// <remarks>
    /// A null has no members and an empty array has no elements, so nothing under either
    /// was ever going to appear.
    /// </remarks>
    private static bool UnreachableIn(string path, IReadOnlyDictionary<string, string> observed)
    {
        foreach (var ancestor in AncestorsOf(path))
        {
            if (!observed.TryGetValue(ancestor, out var token))
            {
                continue;
            }

            var tokens = token.Split('|');

            if (tokens.All(one => one == "null"))
            {
                return true;
            }

            if (tokens.Contains("array", StringComparer.Ordinal) && !observed.ContainsKey(ancestor + "[]"))
            {
                return true;
            }
        }

        return false;
    }

    /// <summary>A token's forms, in the order signatures store them, with <c>null</c> dropped.</summary>
    private static string[] WithoutNull(string token) =>
        token.Split('|').Where(one => one != "null").ToArray();

    /// <summary>
    /// Whether two tokens differ only over whether a value arrived.
    /// </summary>
    /// <remarks>
    /// Drop <c>null</c> from both sides and compare what is left. <c>date</c> against
    /// <c>date|null</c> leaves the same form on each. <c>date</c> against <c>null</c>
    /// leaves one side with nothing, and a side that recorded no form makes no claim
    /// about the form — so there is nothing there to have moved. <c>digits:9</c> against
    /// <c>text</c> leaves two different forms, which is drift and stays reported.
    /// </remarks>
    private static bool NullabilityOnly(string before, string after)
    {
        var left = WithoutNull(before);
        var right = WithoutNull(after);

        return left.Length == 0 || right.Length == 0 || left.SequenceEqual(right, StringComparer.Ordinal);
    }

    /// <summary>How a baseline comparison came out.</summary>
    /// <param name="Changes">Differences that are genuine drift.</param>
    /// <param name="Nullable">Differences excused as "a nullable field happened not to arrive".</param>
    /// <param name="Unreachable">Paths excused as sitting under a null or empty parent.</param>
    public sealed record BaselineComparison(IReadOnlyList<Change> Changes, int Nullable, int Unreachable);

    /// <summary>
    /// The recording held against a live response, with the differences a recording
    /// cannot speak to left out.
    /// </summary>
    /// <remarks>
    /// <para>
    /// A baseline is one organization's response on one afternoon, so much of what
    /// separates it from today's run is not the API moving — it is a different subject,
    /// or the same subject whose Pub 78 row lapsed since. Two kinds of difference fall
    /// out of that, and neither is drift.
    /// </para>
    /// <para>
    /// Nullability. <c>pub78_city</c> was <c>text</c> when the recording was made and is
    /// <c>null</c> now. The field is still there and still declared nullable; this
    /// organization simply has no Pub 78 city. Only a move between two forms a value
    /// actually took — <c>digits:9</c> to <c>text</c> — says the API changed.
    /// </para>
    /// <para>
    /// Reachability. <c>organization_types</c> arrived null, so the paths beneath it had
    /// nowhere to be and read as removed. <see cref="CoverageDiff"/> already excuses that
    /// against the contract; a recording needs it in both directions, because which side
    /// has the populated parent is an accident of which ran first.
    /// </para>
    /// <para>
    /// Both are counted rather than dropped, so a green run still says how much it passed
    /// over. What the recording cannot answer, the contract checks do: a field that must
    /// not be null is declared that way in <c>response-contract.json</c>, and
    /// <see cref="ContractDiff"/> fails on it there.
    /// </para>
    /// </remarks>
    public static BaselineComparison BaselineDiff(
        IReadOnlyDictionary<string, string> before,
        IReadOnlyDictionary<string, string> current)
    {
        var changes = new List<Change>();
        var nullable = 0;
        var unreachable = 0;

        foreach (var entry in before)
        {
            if (current.TryGetValue(entry.Key, out var token))
            {
                if (token == entry.Value)
                {
                    continue;
                }

                if (NullabilityOnly(entry.Value, token))
                {
                    nullable++;

                    continue;
                }

                changes.Add(new Change("changed", entry.Key, From: entry.Value, To: token));

                continue;
            }

            if (UnreachableIn(entry.Key, current))
            {
                unreachable++;

                continue;
            }

            changes.Add(new Change("removed", entry.Key, Token: entry.Value));
        }

        foreach (var entry in current)
        {
            if (before.ContainsKey(entry.Key))
            {
                continue;
            }

            if (UnreachableIn(entry.Key, before))
            {
                unreachable++;

                continue;
            }

            changes.Add(new Change("added", entry.Key, Token: entry.Value));
        }

        return new BaselineComparison(Sort(changes), nullable, unreachable);
    }

    // --- the package's own prediction ----------------------------------------
    //
    // Everything above compares one live response against another recorded
    // earlier, which answers "did the API move?" but never "does the API still
    // match what this package tells its users?". The second question is the one
    // with a caller on the other end of it: Nonprofit.BmfStatus promises a bool,
    // and a user writes `if (np.BmfStatus == true)` on the strength of that
    // promise. Nothing in a self-recorded baseline can notice when the API
    // disagrees, because the baseline is the API's own output — it agrees with
    // itself by construction.
    //
    // response-contract.json is the other side of that comparison: the shape this
    // package predicts, in the same token vocabulary as a signature so the two
    // can be held against each other directly. It is checked in, identical for
    // everyone, and derived from the documented model rather than from anyone's
    // account — so a diff to it is a deliberate change to what the SDK promises,
    // reviewable as such, rather than a record of what one organization looked
    // like on one afternoon.

    /// <summary>
    /// The flat expected signature for one endpoint, built from the shared parts.
    /// </summary>
    /// <remarks>
    /// The record is described once and used for both endpoints, so single and bulk
    /// cannot drift apart in the contract the way they can on the wire — where
    /// <c>bmf_status</c> arrives as a string from one and a bool from the other. One
    /// description means one of those two has to be reported as wrong.
    /// </remarks>
    public static SortedDictionary<string, string> ComposeExpected(JsonElement contract, string kind)
    {
        var single = kind == "single";
        var prefix = single ? "data." : "data[].";
        var expected = new SortedDictionary<string, string>(StringComparer.Ordinal);

        foreach (var field in contract.GetProperty("envelope").EnumerateObject())
        {
            expected[field.Name] = field.Value.GetString()!;
        }

        expected["data"] = single ? "null|object" : "array|null";
        expected["errors[]"] = "object";
        expected["errors[].eins[]"] = "string";

        foreach (var field in contract.GetProperty("errorDetail").EnumerateObject())
        {
            expected["errors[]." + field.Name] = field.Value.GetString()!;
        }

        if (!single)
        {
            expected["data[]"] = "object";
        }

        foreach (var field in contract.GetProperty("nonprofit").EnumerateObject())
        {
            expected[prefix + field.Name] = field.Value.GetString()!;
        }

        // Nullable elements, not just a nullable array: the API sends a null in the
        // list where Publication 78 has a deductibility row it cannot resolve, so a
        // caller reading the first entry has to check. Nonprofit.OrganizationTypes
        // says the same thing by dropping them.
        expected[prefix + "organization_types[]"] = "null|object";

        foreach (var field in contract.GetProperty("organizationType").EnumerateObject())
        {
            expected[prefix + "organization_types[]." + field.Name] = field.Value.GetString()!;
        }

        return expected;
    }

    /// <summary>
    /// Paths the live response carries a value the contract permits no form of.
    /// </summary>
    /// <remarks>
    /// Paths the contract has never heard of are <see cref="CoverageDiff"/>'s to report,
    /// so a field the API invented is one failure rather than two.
    /// </remarks>
    public static IReadOnlyList<Change> ContractDiff(
        IReadOnlyDictionary<string, string> expected,
        IReadOnlyDictionary<string, string> observed)
    {
        var changes = new List<Change>();

        foreach (var entry in observed)
        {
            if (!expected.TryGetValue(entry.Key, out var allowed))
            {
                continue;
            }

            var offending = entry.Value.Split('|').Where(one => !Permits(allowed, one)).ToArray();

            if (offending.Length > 0)
            {
                changes.Add(new Change("changed", entry.Key, From: allowed, To: string.Join("|", offending)));
            }
        }

        return Sort(changes);
    }

    /// <summary>How a coverage comparison came out.</summary>
    /// <param name="Changes">Fields that appeared unpredicted, or predicted fields that stopped arriving.</param>
    /// <param name="Unreachable">Predicted paths excused as sitting under a null or empty parent.</param>
    public sealed record CoverageComparison(IReadOnlyList<Change> Changes, int Unreachable);

    /// <summary>
    /// Fields the API sent that the package does not predict, and fields it predicts that
    /// the API did not send.
    /// </summary>
    /// <remarks>
    /// <para>
    /// Both directions fail. An unpredicted field is readable only by a caller who
    /// already knows to look — <c>nonprofit.Get("field")</c> hides it from everyone else —
    /// and a predicted field that stopped arriving breaks every caller that reads it. The
    /// typed model notices neither, so this is the only place either one is caught.
    /// </para>
    /// <para>
    /// The exception is a path that had nowhere to arrive: <c>errors[].reason</c> while
    /// <c>errors</c> is null, <c>data.organization_types[].organization_type</c> while
    /// that array is null or empty. The parent already accounts for the child's absence,
    /// and every successful response has a null <c>errors</c> — reporting those would fail
    /// every green run and say nothing. They are counted as unreachable.
    /// </para>
    /// <para>
    /// A container that vanished is reported once, at its shallowest path: a <c>data</c>
    /// that stopped arriving is one failure, not fifty-nine.
    /// </para>
    /// </remarks>
    public static CoverageComparison CoverageDiff(
        IReadOnlyDictionary<string, string> expected,
        IReadOnlyDictionary<string, string> observed)
    {
        var changes = new List<Change>();

        foreach (var entry in observed)
        {
            if (!expected.ContainsKey(entry.Key))
            {
                changes.Add(new Change("added", entry.Key, Token: entry.Value));
            }
        }

        var missing = expected.Where(entry => !observed.ContainsKey(entry.Key))
            .ToDictionary(entry => entry.Key, entry => entry.Value, StringComparer.Ordinal);

        var unreachable = 0;

        foreach (var entry in missing)
        {
            if (UnreachableIn(entry.Key, observed))
            {
                unreachable++;

                continue;
            }

            if (AncestorsOf(entry.Key).Any(missing.ContainsKey))
            {
                continue;
            }

            changes.Add(new Change("removed", entry.Key, Token: entry.Value));
        }

        return new CoverageComparison(Sort(changes), unreachable);
    }
}
