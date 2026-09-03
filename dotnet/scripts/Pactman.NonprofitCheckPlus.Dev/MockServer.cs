using System;
using System.Globalization;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Threading;
using System.Threading.Tasks;

namespace Pactman.NonprofitCheckPlus.Dev;

/// <summary>
/// Serves the fixture API on a loopback port, for the examples and for CI.
/// </summary>
/// <remarks>
/// An in-process <see cref="HttpListener"/> does the serving, so there is no child
/// process to start, no port handshake to wait on, and nothing left running if a test
/// throws. Always bound to 127.0.0.1.
/// </remarks>
public sealed class MockServer : IDisposable
{
    private readonly HttpListener _listener;
    private readonly MockRouter _router;
    private readonly CancellationTokenSource _shutdown = new();
    private readonly Task _loop;

    private bool _stopped;

    private MockServer(HttpListener listener, MockRouter router, int port, string apiKey)
    {
        _listener = listener;
        _router = router;
        Port = port;
        ApiKey = apiKey;
        _loop = Task.Run(ServeAsync);
    }

    /// <summary>The port the server is listening on.</summary>
    public int Port { get; }

    /// <summary>The bearer token the server accepts.</summary>
    public string ApiKey { get; }

    /// <summary>The loopback URL the server is listening on.</summary>
    public string BaseUrl => string.Format(CultureInfo.InvariantCulture, "http://127.0.0.1:{0}", Port);

    /// <summary>Starts the server.</summary>
    /// <param name="port">The port to bind, or <see langword="null"/> to pick a free one.</param>
    /// <param name="apiKey">The key to accept, or <see langword="null"/> for the default.</param>
    /// <returns>A running server. Dispose it to stop.</returns>
    public static MockServer Start(int? port = null, string? apiKey = null)
    {
        var chosen = port ?? FreePort();
        var key = apiKey ?? Environment.GetEnvironmentVariable("MOCK_API_KEY") ?? "mock-key";

        var listener = new HttpListener();
        listener.Prefixes.Add(string.Format(CultureInfo.InvariantCulture, "http://127.0.0.1:{0}/", chosen));
        listener.Start();

        return new MockServer(listener, new MockRouter(key), chosen, key);
    }

    private async Task ServeAsync()
    {
        while (!_shutdown.IsCancellationRequested)
        {
            HttpListenerContext context;

            try
            {
                context = await _listener.GetContextAsync().ConfigureAwait(false);
            }
            catch (Exception) when (_shutdown.IsCancellationRequested)
            {
                return;
            }
            catch (HttpListenerException)
            {
                return;
            }
            catch (ObjectDisposedException)
            {
                return;
            }

            // Each request is served on its own, so the deliberately slow control EIN
            // holds up only the caller that asked for it.
            _ = Task.Run(() => RespondAsync(context));
        }
    }

    private async Task RespondAsync(HttpListenerContext context)
    {
        try
        {
            string body;

            using (var reader = new StreamReader(context.Request.InputStream, Encoding.UTF8))
            {
                body = await reader.ReadToEndAsync().ConfigureAwait(false);
            }

            var response = await _router.HandleAsync(
                context.Request.HttpMethod,
                context.Request.Url?.AbsolutePath ?? "/",
                context.Request.Headers["Authorization"],
                body,
                _shutdown.Token).ConfigureAwait(false);

            var payload = Encoding.UTF8.GetBytes(response.Body.ToJsonString());

            context.Response.StatusCode = response.Status;
            context.Response.ContentType = "application/json";
            context.Response.Headers["X-Request-Id"] = "mock-" + Guid.NewGuid().ToString("N")[..8];

            foreach (var header in response.Headers)
            {
                context.Response.Headers[header.Key] = header.Value;
            }

            context.Response.ContentLength64 = payload.Length;
            await context.Response.OutputStream.WriteAsync(payload).ConfigureAwait(false);
        }
        catch (Exception)
        {
            // A client that hung up mid-response, or a shutdown racing a request in
            // flight. Never take the server down over one connection.
        }
        finally
        {
            try
            {
                context.Response.Close();
            }
            catch (Exception)
            {
                // Already closed by the failure above.
            }
        }
    }

    /// <summary>Stops the server and releases the port.</summary>
    public void Dispose()
    {
        if (_stopped)
        {
            return;
        }

        _stopped = true;
        _shutdown.Cancel();

        try
        {
            _listener.Stop();
            _listener.Close();
        }
        catch (Exception)
        {
            // Already torn down.
        }

        try
        {
            _loop.Wait(TimeSpan.FromSeconds(2));
        }
        catch (Exception)
        {
            // The loop is unwinding from the cancel above; nothing to add.
        }

        _shutdown.Dispose();
    }

    /// <summary>Binds port 0 to have the OS name a free port, then releases it.</summary>
    private static int FreePort()
    {
        var probe = new TcpListener(IPAddress.Loopback, 0);
        probe.Start();

        try
        {
            return ((IPEndPoint)probe.LocalEndpoint).Port;
        }
        finally
        {
            probe.Stop();
        }
    }
}
