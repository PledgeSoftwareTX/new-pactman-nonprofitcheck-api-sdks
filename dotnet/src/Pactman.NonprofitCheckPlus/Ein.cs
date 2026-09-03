using System;
using System.Collections.Generic;
using System.Globalization;
using System.Text.RegularExpressions;
using Pactman.NonprofitCheckPlus.Exceptions;

namespace Pactman.NonprofitCheckPlus
{
    /// <summary>
    /// EIN normalization and validation.
    /// </summary>
    /// <remarks>
    /// Formatting validation only. Passing these checks says nothing about whether an
    /// organization is tax-exempt, in good standing, or eligible for anything — only that
    /// the value is shaped like an EIN. No IRS prefix rules are applied.
    /// </remarks>
    public static class Ein
    {
        /// <summary>Number of digits in an EIN.</summary>
        public const int Length = 9;

        /// <summary>
        /// Accepted input shapes: nine digits, optionally with the conventional hyphen
        /// after the two-digit prefix. Surrounding whitespace is ignored.
        /// </summary>
        private static readonly Regex Pattern =
            new Regex(@"^\d{2}-?\d{7}$", RegexOptions.CultureInvariant | RegexOptions.Compiled);

        /// <summary>
        /// Normalizes an EIN to the nine-digit form the API expects.
        /// </summary>
        /// <remarks><c>"41-1787097"</c> and <c>"411787097"</c> both normalize to <c>"411787097"</c>.</remarks>
        /// <param name="value">The EIN as supplied.</param>
        /// <param name="index">Position in the input collection, for a bulk call's error message.</param>
        /// <returns>The nine-digit EIN.</returns>
        /// <exception cref="PactmanValidationException">The value is not shaped like an EIN.</exception>
        public static string Normalize(string? value, int? index = null)
        {
            var issue = Inspect(value, index);

            if (issue != null)
            {
                throw new PactmanValidationException(issue.Message, new[] { issue });
            }

            return Clean(value!);
        }

        /// <summary>
        /// Normalizes a collection of EINs, reporting every failure at once.
        /// </summary>
        /// <remarks>
        /// <para>
        /// Duplicates are preserved and order is retained; see
        /// <see cref="Configuration.BulkRequestOptions.Dedupe"/> for the opt-in behavior.
        /// </para>
        /// <para>
        /// <b>Watch for EINs that have been through a numeric type.</b> <c>042103594</c>
        /// read as an <see langword="int"/> — from a spreadsheet column, a JSON number, a
        /// database <c>bigint</c> — is <c>42103594</c>: the leading zero is gone and the
        /// value is a different EIN. Keep EINs as strings end to end.
        /// </para>
        /// </remarks>
        /// <param name="values">The EINs as supplied.</param>
        /// <returns>The nine-digit EINs, in input order.</returns>
        /// <exception cref="PactmanValidationException">
        /// Any item is not shaped like an EIN. The exception's
        /// <see cref="PactmanValidationException.Issues"/> identify each failing item by
        /// index and original value.
        /// </exception>
        public static IReadOnlyList<string> NormalizeMany(IEnumerable<string?> values)
        {
            if (values is null)
            {
                throw new PactmanValidationException("A collection of EINs is required.");
            }

            var issues = new List<ValidationIssue>();
            var normalized = new List<string>();
            var count = 0;

            foreach (var value in values)
            {
                var issue = Inspect(value, count);
                count++;

                if (issue != null)
                {
                    issues.Add(issue);

                    continue;
                }

                normalized.Add(Clean(value!));
            }

            if (issues.Count > 0)
            {
                var positions = new List<string>(issues.Count);

                foreach (var issue in issues)
                {
                    positions.Add(issue.Index?.ToString(CultureInfo.InvariantCulture) ?? "?");
                }

                throw new PactmanValidationException(
                    string.Format(
                        CultureInfo.InvariantCulture,
                        "{0} of {1} EINs are invalid (at index {2}). No request was sent.",
                        issues.Count,
                        count,
                        string.Join(", ", positions)),
                    issues);
            }

            return normalized;
        }

        /// <summary>True when the value is shaped like an EIN. Never throws.</summary>
        /// <param name="value">The value to test.</param>
        /// <returns><see langword="true"/> when the value is EIN-shaped.</returns>
        public static bool IsValid(string? value) => Inspect(value, null) is null;

        /// <summary>Strips a value that <see cref="Inspect"/> has already confirmed is EIN-shaped.</summary>
        private static string Clean(string value) => value.Trim().Replace("-", string.Empty);

        private static ValidationIssue? Inspect(string? value, int? index)
        {
            var at = index is null
                ? string.Empty
                : string.Format(CultureInfo.InvariantCulture, " at index {0}", index.Value);

            if (value is null)
            {
                return new ValidationIssue("EIN" + at + " is required.", index, null);
            }

            var trimmed = value.Trim();

            if (trimmed.Length == 0)
            {
                return new ValidationIssue("EIN" + at + " is empty.", index, value);
            }

            if (!Pattern.IsMatch(trimmed))
            {
                return new ValidationIssue(
                    string.Format(
                        CultureInfo.InvariantCulture,
                        "EIN{0} must be {1} digits, optionally hyphenated as XX-XXXXXXX. Received \"{2}\".",
                        at,
                        Length,
                        trimmed),
                    index,
                    value);
            }

            return null;
        }
    }
}
