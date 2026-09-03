using System.Text.Json;

namespace Pactman.NonprofitCheckPlus.Models
{
    /// <summary>
    /// A response body as the SDK received it: parsed JSON, unparseable text, or nothing.
    /// </summary>
    /// <remarks>
    /// An unparseable body is still evidence. A server that answers 200 with an HTML
    /// error page leaves that page in <see cref="Text"/> rather than having it
    /// discarded, so the value that reaches your logs is the one that actually arrived.
    /// </remarks>
    public sealed class ResponseBody
    {
        private ResponseBody(JsonElement? json, string? text)
        {
            Json = json;
            Text = text;
        }

        /// <summary>An empty body.</summary>
        public static ResponseBody Empty { get; } = new ResponseBody(null, null);

        /// <summary>The parsed body, when it was JSON.</summary>
        public JsonElement? Json { get; }

        /// <summary>The raw body text, when it was not parseable JSON.</summary>
        public string? Text { get; }

        /// <summary>True when the body parsed as JSON.</summary>
        public bool IsJson => Json.HasValue;

        /// <summary>True when the server sent no body at all.</summary>
        public bool IsEmpty => !Json.HasValue && Text is null;

        /// <summary>
        /// The response envelope, or an undefined element when the body was not a JSON object.
        /// </summary>
        public JsonElement Envelope =>
            Json.HasValue && Json.Value.ValueKind == JsonValueKind.Object ? Json.Value : default;

        /// <summary>Wraps a parsed JSON body.</summary>
        /// <param name="json">The parsed body.</param>
        /// <returns>A body carrying the parsed JSON.</returns>
        public static ResponseBody FromJson(JsonElement json) => new ResponseBody(json, null);

        /// <summary>Wraps a body that could not be parsed as JSON.</summary>
        /// <param name="text">The raw body text.</param>
        /// <returns>A body carrying the raw text.</returns>
        public static ResponseBody FromText(string text) => new ResponseBody(null, text);

        /// <summary>The body as text, however it arrived.</summary>
        /// <returns>The raw JSON, the raw text, or an empty string.</returns>
        public override string ToString() =>
            Json.HasValue ? Json.Value.GetRawText() : Text ?? string.Empty;
    }
}
