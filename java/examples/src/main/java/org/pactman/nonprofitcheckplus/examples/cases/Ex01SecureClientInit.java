package org.pactman.nonprofitcheckplus.examples.cases;

import java.util.LinkedHashMap;
import java.util.Map;
import org.pactman.nonprofitcheckplus.PactmanClient;
import org.pactman.nonprofitcheckplus.PactmanEnvironment;
import org.pactman.nonprofitcheckplus.config.PactmanClientOptions;
import org.pactman.nonprofitcheckplus.examples.support.Example;
import org.pactman.nonprofitcheckplus.examples.support.ExampleContext;
import org.pactman.nonprofitcheckplus.examples.support.ExampleFailedException;
import org.pactman.nonprofitcheckplus.examples.support.Output;
import org.pactman.nonprofitcheckplus.exceptions.PactmanConfigurationException;

/**
 * EX-01 — Secure client initialization.
 *
 * <p>Loads the API key from an environment variable, selects the environment,
 * configures a finite timeout, and builds one reusable client. Then it proves
 * the key does not leak into logs, debug output, or exceptions.
 */
public final class Ex01SecureClientInit implements Example {

    @Override
    public String id() {
        return "ex-01";
    }

    @Override
    public String title() {
        return "Secure client initialization and credential redaction";
    }

    @Override
    public void run(String[] args) {
        // 1. The key comes from the environment. It is never a literal in
        //    source, never committed, and never shipped inside a client-side
        //    artifact — anyone who decompiles a binary holding this key owns
        //    your quota.
        String apiKey = ExampleContext.requireApiKey();

        // 2. One client, built once, reused for the life of the process.
        //    Constructing a client per request throws away connection reuse and
        //    any throttle state.
        PactmanClientOptions.Builder options = PactmanClientOptions.builder()
                .apiKey(apiKey)
                // Production is the default; naming it makes the intent explicit
                // at review time.
                .environment(PactmanEnvironment.PRODUCTION)
                // 3. A finite timeout. The default is 30s and there is no way to
                //    disable it, but a caller-facing service usually wants
                //    something shorter.
                .timeoutMs(10_000);

        // A mock or a host Pactman gave you directly overrides `environment`.
        String override = ExampleContext.baseUrlOverride();

        if (override != null) {
            options.baseUrl(override);
        }

        try (PactmanClient client = new PactmanClient(options.build())) {
            Output.heading("Resolved configuration");
            Output.field("baseUrl", client.baseUrl());
            Output.field("environment", client.environment());
            Output.field("timeoutMs", client.timeoutMs());
            Output.field("SDK default timeout", PactmanClientOptions.DEFAULT_TIMEOUT_MS);

            // 4. Every diagnostic surface is checked against the real key. None
            //    of them contain it — the key is not a property of the client,
            //    and the exception types never copy it into a message or a
            //    serialized field.
            PactmanConfigurationException caught = null;

            try {
                new PactmanClient(
                        PactmanClientOptions.builder().apiKey(apiKey).baseUrl("not-a-url").build());
            } catch (PactmanConfigurationException failure) {
                caught = failure;
            }

            if (caught == null) {
                throw new ExampleFailedException(
                        "A malformed baseUrl should have been rejected at construction.");
            }

            Map<String, String> surfaces = new LinkedHashMap<>();
            surfaces.put("client.toString()", client.toString());
            surfaces.put("client.toMap()", String.valueOf(client.toMap()));
            surfaces.put("exception.getMessage()", String.valueOf(caught.getMessage()));
            surfaces.put("exception.toMap()", String.valueOf(caught.toMap()));
            surfaces.put("exception stack trace", stackTraceOf(caught));

            Output.heading("Credential redaction");
            boolean leaked = false;

            for (Map.Entry<String, String> surface : surfaces.entrySet()) {
                boolean contains = surface.getValue().contains(apiKey);
                leaked = leaked || contains;
                Output.field(surface.getKey(), contains ? "LEAKED THE KEY" : "clean");
            }

            Output.heading("Client as printed");
            System.out.println("  " + client);
            System.out.println("  " + client.toMap());

            Output.note("The key is sent only as an Authorization header at request time.\n"
                    + "Rotate it if it is ever printed, logged, or committed.");

            if (leaked) {
                throw new ExampleFailedException("The API key reached a diagnostic surface.");
            }
        }
    }

    private static String stackTraceOf(Throwable error) {
        java.io.StringWriter buffer = new java.io.StringWriter();
        error.printStackTrace(new java.io.PrintWriter(buffer));

        return buffer.toString();
    }
}
