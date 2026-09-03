using System;
using System.Globalization;

namespace Pactman.NonprofitCheckPlus.Examples;

/// <summary>
/// Parsing for the date format this API returns.
/// </summary>
/// <remarks>
/// Every timestamp arrives as <c>M/DD/YYYY h:mm:ss AM</c>. Parse it; never reformat it in
/// place, and never store the reformatted value as if it were what the API said. A value
/// that will not parse is reported as unparseable rather than silently treated as absent —
/// the difference matters when the date is the evidence for a decision.
/// </remarks>
public static class ApiDate
{
    private static readonly string[] Formats =
    {
        "M/d/yyyy h:mm:ss tt",
        "M/d/yyyy, h:mm:ss tt",
        "M/d/yyyy H:mm:ss",
    };

    /// <summary>Parses an API timestamp, or returns <see langword="null"/> when there is nothing to parse.</summary>
    /// <param name="value">The timestamp as the API sent it.</param>
    /// <returns>The parsed value, or <see langword="null"/>.</returns>
    public static DateTime? Parse(object? value)
    {
        if (value is not string text || string.IsNullOrWhiteSpace(text))
        {
            return null;
        }

        // Newer runtimes format times with a narrow no-break space; the API sends a
        // plain one, and an exact-format parse fails on the difference alone.
        var trimmed = text.Trim().Replace(' ', ' ').Replace(' ', ' ');

        if (DateTime.TryParseExact(
                trimmed,
                Formats,
                CultureInfo.InvariantCulture,
                DateTimeStyles.None,
                out var exact))
        {
            return exact;
        }

        // A format the API changed or a value this example has not seen. Fall back to
        // the general parser rather than reporting a date as missing.
        return DateTime.TryParse(trimmed, CultureInfo.InvariantCulture, DateTimeStyles.None, out var loose)
            ? loose
            : null;
    }

    /// <summary>Whole days since a timestamp, or <see langword="null"/> when it could not be parsed.</summary>
    /// <param name="value">The timestamp as the API sent it.</param>
    /// <param name="now">The moment to measure from; defaults to now.</param>
    /// <returns>The age in whole days, or <see langword="null"/>.</returns>
    public static int? AgeInDays(object? value, DateTime? now = null)
    {
        var parsed = Parse(value);

        return parsed is null ? null : (int)((now ?? DateTime.Now) - parsed.Value).TotalDays;
    }

    /// <summary>An ISO-8601 stamp for "when we looked", to store beside a verification record.</summary>
    /// <returns>The current time, in ISO-8601.</returns>
    public static string CheckedAt() =>
        DateTime.UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ", CultureInfo.InvariantCulture);
}
