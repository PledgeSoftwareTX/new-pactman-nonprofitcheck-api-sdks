using System;
using System.Collections.Generic;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace Pactman.NonprofitCheckPlus.Tests.Support;

/// <summary>One request that reached <see cref="FakeHandler"/>.</summary>
public sealed class RecordedRequest
{
    public RecordedRequest(string method, Uri uri, IReadOnlyDictionary<string, string> headers, string? body)
    {
        Method = method;
        Uri = uri;
        Headers = headers;
        Body = body;
    }

    public string Method { get; }

    public Uri Uri { get; }

    /// <summary>Every header sent, request and content headers together, keyed case-insensitively.</summary>
    public IReadOnlyDictionary<string, string> Headers { get; }

    public string? Body { get; }

    public string Path => Uri.AbsolutePath;

    public string? Header(string name) => Headers.TryGetValue(name, out var value) ? value : null;

    /// <summary>The request body parsed as JSON, or <see langword="null"/> when there was none.</summary>
    public JsonNode? JsonBody() => Body is null ? null : JsonNode.Parse(Body);

    /// <summary>The request body as a list of strings — the shape the bulk endpoint takes.</summary>
    public IReadOnlyList<string> StringListBody() =>
        Body is null ? Array.Empty<string>() : JsonSerializer.Deserialize<List<string>>(Body)!;
}
