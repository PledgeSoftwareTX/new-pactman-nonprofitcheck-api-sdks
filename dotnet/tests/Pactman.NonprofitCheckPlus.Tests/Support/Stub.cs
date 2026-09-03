using System;
using System.Collections.Generic;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace Pactman.NonprofitCheckPlus.Tests.Support;

/// <summary>One canned outcome for <see cref="FakeHandler"/> to serve.</summary>
public sealed class Stub
{
    private Stub(int status, string? body, IReadOnlyDictionary<string, string> headers, Exception? throws, TimeSpan? hang)
    {
        Status = status;
        Body = body;
        Headers = headers;
        Throws = throws;
        Hang = hang;
    }

    public int Status { get; }

    public string? Body { get; }

    public IReadOnlyDictionary<string, string> Headers { get; }

    /// <summary>Thrown instead of answering, to simulate a connection failure.</summary>
    public Exception? Throws { get; }

    /// <summary>Waits this long before answering, to let a deadline expire.</summary>
    public TimeSpan? Hang { get; }

    public static Stub Json(JsonNode body, int status = 200, IReadOnlyDictionary<string, string>? headers = null) =>
        new(status, body.ToJsonString(), headers ?? Empty, null, null);

    public static Stub Text(string body, int status = 200, IReadOnlyDictionary<string, string>? headers = null) =>
        new(status, body, headers ?? Empty, null, null);

    public static Stub Empty204() => new(204, null, Empty, null, null);

    public static Stub Failure(Exception exception) => new(0, null, Empty, exception, null);

    public static Stub Hangs(TimeSpan duration) => new(0, null, Empty, null, duration);

    /// <summary>An error envelope shaped the way the API sends one.</summary>
    public static Stub Error(
        int status,
        string? message = null,
        JsonNode? errors = null,
        IReadOnlyDictionary<string, string>? headers = null)
    {
        var envelope = new JsonObject
        {
            ["code"] = status,
            ["message"] = message,
            ["errors"] = errors,
        };

        return Json(envelope, status, headers);
    }

    private static readonly Dictionary<string, string> Empty = new(StringComparer.OrdinalIgnoreCase);
}
