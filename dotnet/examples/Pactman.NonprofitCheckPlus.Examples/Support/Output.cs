using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Text.Json;
using Pactman.NonprofitCheckPlus.Models;

namespace Pactman.NonprofitCheckPlus.Examples;

/// <summary>
/// Terminal formatting for the examples.
/// </summary>
/// <remarks>
/// The only thing here worth borrowing is <see cref="Display"/>: it prints "the API
/// returned no such field" differently from "the API returned null", because in this API
/// those route differently and a display that flattens them into one blank has thrown
/// away a finding.
/// </remarks>
public static class Output
{
    /// <summary>How a field the API did not return is shown.</summary>
    public const string NotReturned = "<not returned>";

    private const string Csi = "\u001b[";
    private const string Reset = "\u001b[0m";

    /// <summary>
    /// Colour, when there is someone there to see it.
    /// </summary>
    /// <remarks>
    /// Off when stdout is redirected, when <c>NO_COLOR</c> is set (no-color.org), or when
    /// <c>TERM</c> says dumb — a captured log stays plain text, with no escape sequences to
    /// confuse whatever reads it next. <c>FORCE_COLOR</c> overrides all of it, for a CI log
    /// that is rendered with colour even though nothing it is written to is a terminal.
    /// </remarks>
    private static bool Colour =>
        Environment.GetEnvironmentVariable("NO_COLOR") is null
        && (Environment.GetEnvironmentVariable("FORCE_COLOR") is not null
            || (!Console.IsOutputRedirected && Environment.GetEnvironmentVariable("TERM") != "dumb"));

    /// <summary>Wraps text in an ANSI code, when colour is on.</summary>
    /// <param name="code">The SGR code to apply.</param>
    /// <param name="text">The text to wrap.</param>
    /// <returns>The text, coloured or plain.</returns>
    public static string Paint(int code, string text) =>
        Colour ? Csi + code.ToString(CultureInfo.InvariantCulture) + "m" + text + Reset : text;

    /// <summary>Prints a section heading with an underline.</summary>
    /// <param name="text">The heading.</param>
    public static void Heading(string text)
    {
        Console.WriteLine();
        Console.WriteLine(Paint(1, text));
        Console.WriteLine(new string('─', Math.Max(8, text.Length)));
    }

    /// <summary>Prints a labelled value in an aligned column.</summary>
    /// <param name="label">The field label.</param>
    /// <param name="value">The value to render.</param>
    public static void Field(string label, object? value) =>
        Console.WriteLine("  {0,-38} {1}", label, Format(value));

    /// <summary>Prints a bulleted line.</summary>
    /// <param name="text">The line.</param>
    public static void Bullet(string text) => Console.WriteLine("  • " + text);

    /// <summary>Prints a dimmed closing note.</summary>
    /// <param name="text">The note.</param>
    public static void Note(string text)
    {
        Console.WriteLine();
        Console.WriteLine(Paint(2, text));
    }

    /// <summary>Prints to standard error.</summary>
    /// <param name="text">The message.</param>
    public static void Error(string text) => Console.Error.WriteLine(text);

    /// <summary>Prints a field, distinguishing "not returned" from "returned as null".</summary>
    /// <param name="source">The model to read.</param>
    /// <param name="field">The wire field name.</param>
    /// <param name="label">A label, when the wire name is not what you want shown.</param>
    public static void DisplayField(DataObject source, string field, string? label = null) =>
        Field(label ?? field, Display(source, field));

    /// <summary>
    /// The field's value for display, or <see cref="NotReturned"/> when the API omitted it.
    /// </summary>
    /// <param name="source">The model to read.</param>
    /// <param name="field">The wire field name.</param>
    /// <returns>The value, or the not-returned marker.</returns>
    public static object? Display(DataObject source, string field) =>
        source.Has(field) ? source.Get(field) : NotReturned;

    /// <summary>
    /// A value as text, for interpolation into a message.
    /// </summary>
    /// <remarks>
    /// The API's fields are weakly typed on the way out — the wire decides their shape, not
    /// this SDK — so casting one straight to a string is a bet. This takes the value it was
    /// given and describes anything that is not a scalar rather than crashing on it.
    /// </remarks>
    /// <param name="value">The value to render.</param>
    /// <returns>The value as text, or an empty string for null.</returns>
    public static string Text(object? value) => value switch
    {
        null => string.Empty,
        string text => text,
        bool flag => flag ? "true" : "false",
        IFormattable formattable => formattable.ToString(null, CultureInfo.InvariantCulture),
        _ => Format(value),
    };

    /// <summary>Renders a value so null, false and 0 stay visibly distinct.</summary>
    /// <param name="value">The value to render.</param>
    /// <returns>The rendered value.</returns>
    public static string Format(object? value) => value switch
    {
        null => Paint(2, "null"),
        bool flag => flag ? "true" : "false",
        string text when text == NotReturned => Paint(2, NotReturned),
        string text => text,
        JsonElement element => element.GetRawText(),
        IReadOnlyDictionary<string, object?> map => JsonSerializer.Serialize(map),
        IEnumerable<object?> items => "[" + string.Join(", ", items.Select(Format)) + "]",
        IFormattable formattable => formattable.ToString(null, CultureInfo.InvariantCulture),
        _ => value.ToString() ?? string.Empty,
    };

    /// <summary>A green check, a red cross, or a dim dash.</summary>
    /// <param name="status">One of <c>pass</c>, <c>fail</c> or <c>skip</c>.</param>
    /// <returns>The coloured mark.</returns>
    public static string Mark(string status) => status switch
    {
        "pass" => Paint(32, "✓"),
        "fail" => Paint(31, "✗"),
        _ => Paint(2, "–"),
    };
}
