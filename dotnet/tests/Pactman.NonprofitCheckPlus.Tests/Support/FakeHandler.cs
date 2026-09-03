using System;
using System.Collections.Generic;
using System.Linq;
using System.Net;
using System.Net.Http;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using System.Text.Json.Nodes;

namespace Pactman.NonprofitCheckPlus.Tests.Support;

/// <summary>
/// Serves stubs in order; the last one repeats once the queue is exhausted, so a
/// retry test can end on a stable outcome.
/// </summary>
public sealed class FakeHandler : HttpMessageHandler
{
    private readonly IReadOnlyList<Stub> _stubs;
    private int _index;

    public FakeHandler(params Stub[] stubs)
    {
        if (stubs.Length == 0)
        {
            throw new ArgumentException("FakeHandler was created with an empty stub list.", nameof(stubs));
        }

        _stubs = stubs;
    }

    /// <summary>Every request this handler was asked to send.</summary>
    public List<RecordedRequest> Requests { get; } = new();

    public int RequestCount => Requests.Count;

    public RecordedRequest LastRequest => Requests[^1];

    /// <summary>A handler that answers every request with one canned response.</summary>
    public static FakeHandler Always(Stub stub) => new(stub);

    /// <summary>A handler that answers every request with one organization.</summary>
    public static FakeHandler Returning(JsonNode data) => Always(Stub.Json(Fixtures.Envelope(data)));

    protected override async Task<HttpResponseMessage> SendAsync(
        HttpRequestMessage request,
        CancellationToken cancellationToken)
    {
        var body = request.Content is null ? null : await request.Content.ReadAsStringAsync(cancellationToken);
        var headers = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);

        foreach (var header in request.Headers)
        {
            headers[header.Key] = string.Join(", ", header.Value);
        }

        if (request.Content is not null)
        {
            foreach (var header in request.Content.Headers)
            {
                headers[header.Key] = string.Join(", ", header.Value);
            }
        }

        Requests.Add(new RecordedRequest(request.Method.Method, request.RequestUri!, headers, body));

        var stub = _stubs[Math.Min(_index, _stubs.Count - 1)];
        _index++;

        if (stub.Throws is not null)
        {
            throw stub.Throws;
        }

        if (stub.Hang is { } hang)
        {
            await Task.Delay(hang, cancellationToken);
        }

        var response = new HttpResponseMessage((HttpStatusCode)stub.Status)
        {
            Content = stub.Body is null
                ? new StringContent(string.Empty)
                : new StringContent(stub.Body, Encoding.UTF8, "application/json"),
        };

        foreach (var header in stub.Headers)
        {
            if (!response.Headers.TryAddWithoutValidation(header.Key, header.Value))
            {
                response.Content.Headers.TryAddWithoutValidation(header.Key, header.Value);
            }
        }

        return response;
    }
}
