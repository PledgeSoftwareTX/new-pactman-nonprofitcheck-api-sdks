using System;
using System.Collections.Generic;
using System.Linq;
using System.Text.Json;
using System.Threading.Tasks;
using Pactman.NonprofitCheckPlus.Configuration;
using Pactman.NonprofitCheckPlus.Dev;
using Pactman.NonprofitCheckPlus.Exceptions;

namespace Pactman.NonprofitCheckPlus.Examples.Cases;

/// <summary>
/// EX-01 — Secure client initialization.
/// </summary>
/// <remarks>
/// Loads the API key from an environment variable, selects the environment, configures a
/// finite timeout, and builds one reusable client. Then it proves the key does not leak
/// into logs, debug output, or exceptions.
/// </remarks>
public sealed class Ex01SecureClientInit : IExample
{
    /// <inheritdoc />
    public string Id => "ex-01";

    /// <inheritdoc />
    public string Title => "Secure client initialization, and proof the key does not leak.";

    /// <inheritdoc />
    public Task RunAsync(string[] args)
    {
        // 1. The key comes from the environment. It is never a literal in source, never
        //    committed, and never shipped to a browser or mobile bundle — anyone who
        //    opens devtools on a page holding this key owns your quota.
        var apiKey = DevEnv.Get(DevEnv.ApiKeyVariable)
            ?? throw new ExampleFailedException(
                "Set PACTMAN_API_KEY before running this example. Load it from your secret "
                + "manager or a .env file excluded from git.");

        var baseUrl = DevEnv.Get("PACTMAN_BASE_URL");

        // 2. One client, built once, reused for the life of the process. Constructing a
        //    client per request throws away connection reuse and any throttle state, and
        //    on a self-owned client leaks sockets through TIME_WAIT.
        using var client = new PactmanClient(new PactmanClientOptions
        {
            ApiKey = apiKey,

            // Production is the default; naming it makes the intent explicit at review time.
            Environment = PactmanEnvironment.Production,

            // A mock or a host Pactman gave you directly overrides Environment.
            BaseUrl = baseUrl,

            // 3. A finite timeout. The default is 30s and there is no way to disable it,
            //    but a caller-facing service usually wants something shorter.
            Timeout = TimeSpan.FromSeconds(10),
        });

        Output.Heading("Resolved configuration");
        Output.Field("BaseUrl", client.BaseUrl);
        Output.Field("Environment", client.Environment?.Name());
        Output.Field("Timeout", client.Timeout);
        Output.Field("SDK default timeout", ClientConfig.DefaultTimeout);

        // 4. Every diagnostic surface is checked against the real key. None of them
        //    contain it: the key is not a field of the client, it lives inside a delegate
        //    the transport calls at send time, and the exception types never copy it into
        //    a message or a serialized field.
        PactmanConfigurationException? caught = null;

        try
        {
            using var broken = new PactmanClient(new PactmanClientOptions
            {
                ApiKey = apiKey,
                BaseUrl = "not-a-url",
            });
        }
        catch (PactmanConfigurationException error)
        {
            caught = error;
        }

        var surfaces = new Dictionary<string, string>(StringComparer.Ordinal)
        {
            ["client.ToString()"] = client.ToString(),
            ["client.ToDictionary()"] = JsonSerializer.Serialize(client.ToDictionary()),
            ["error.Message"] = caught?.Message ?? string.Empty,
            ["error.ToDictionary()"] = JsonSerializer.Serialize(caught?.ToDictionary()),

            // The whole exception, stack trace included — the path by which a credential
            // most often reaches an error tracker or a support ticket.
            ["error.ToString()"] = caught?.ToString() ?? string.Empty,
        };

        Output.Heading("Credential redaction");

        var leaked = new List<string>();

        foreach (var surface in surfaces)
        {
            var clean = !surface.Value.Contains(apiKey, StringComparison.Ordinal);

            if (!clean)
            {
                leaked.Add(surface.Key);
            }

            Output.Field(surface.Key, clean ? "clean" : "LEAKED THE KEY");
        }

        Output.Heading("Client as printed");

        foreach (var field in client.ToDictionary())
        {
            Output.Field(field.Key, field.Value);
        }

        Output.Field("Configuration error type", caught?.GetType().Name ?? "none");

        Output.Note(
            "The key is sent only as an Authorization header at request time. Rotate it if\n"
            + "it is ever printed, logged, or committed.");

        if (leaked.Count > 0)
        {
            throw new ExampleFailedException(
                "The API key reached these surfaces: " + string.Join(", ", leaked));
        }

        return Task.CompletedTask;
    }
}
