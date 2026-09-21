package org.pactman.nonprofitcheckplus.devtools;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Arrays;
import java.util.Map;

/**
 * The development tools.
 *
 * <pre>
 *   mock [--port N]         run the stand-in API until interrupted
 *   contract                print the signature this package predicts
 *   smoke-live [options]    check a live deployment against the contract
 * </pre>
 *
 * <p>None of this ships in the published artifact. {@code smoke-live} spends
 * real quota against a real key and is deliberately not part of {@code verify}.
 */
public final class Tools {

    private Tools() {
    }

    /**
     * Entry point.
     *
     * @param args the command and its options.
     * @throws IOException when a server cannot be bound or a file cannot be read.
     */
    public static void main(String[] args) throws IOException {
        String command = args.length == 0 ? "help" : args[0];
        String[] rest = args.length == 0 ? new String[0] : Arrays.copyOfRange(args, 1, args.length);

        switch (command) {
            case "mock":
                mock();
                break;
            case "contract":
                contract();
                break;
            case "smoke-live":
                if (SmokeLive.run(rest) != 0) {
                    throw new IllegalStateException("The live smoke check reported failures.");
                }
                break;
            case "baseline-record":
                recordBaseline(rest);
                break;
            default:
                help();
        }
    }

    private static void help() {
        System.out.println("Pactman Nonprofit Check Plus — dev tools");
        System.out.println();
        System.out.println("  mock         run the stand-in API until interrupted");
        System.out.println("  contract     print the signature this package predicts");
        System.out.println("  smoke-live       check a live deployment against the contract and"
                + " the committed recording");
        System.out.println("  baseline-record  rewrite the committed recording from a live deployment");
        System.out.println();
        System.out.println("  mvn -q -pl devtools exec:java -Dexec.args=\"mock\"");
        System.out.println("  PACTMAN_API_KEY=... mvn -q -pl devtools exec:java \\");
        System.out.println("      -Dexec.args=\"smoke-live\"");
    }

    /**
     * Rewrites the committed baseline. Run from the {@code java/} directory, which is
     * where {@code mvn -pl devtools exec:java} runs.
     *
     * @param rest options passed through to {@link SmokeLive#run}.
     * @throws IOException when the recording cannot be written.
     */
    private static void recordBaseline(String[] rest) throws IOException {
        Path target = Path.of(ContractResources.BASELINE_SOURCE);

        if (!Files.isDirectory(target.getParent())) {
            throw new IllegalStateException(
                    "Run baseline-record from the java/ directory; " + target + " is not there.");
        }

        String[] args = Arrays.copyOf(rest, rest.length + 2);
        args[rest.length] = "--record";
        args[rest.length + 1] = target.toString();

        if (SmokeLive.run(args) != 0) {
            throw new IllegalStateException(
                    "The live responses break the contract; fix that before recording them.");
        }
    }

    private static void mock() throws IOException {
        String apiKey = System.getenv().getOrDefault("MOCK_API_KEY", "mock-key");

        try (FixtureApi api = FixtureApi.start(apiKey)) {
            System.out.println("Fixture API listening on " + api.baseUrl());
            System.out.println("  API key : " + apiKey);
            System.out.println("  EINs    : " + String.join(", ", Fixtures.eins()));
            System.out.println();
            System.out.println("Ctrl-C to stop.");

            // The server's own threads are daemons, so hold the main thread.
            try {
                Thread.currentThread().join();
            } catch (InterruptedException stopped) {
                Thread.currentThread().interrupt();
            }
        }
    }

    private static void contract() {
        Map<String, Object> contract = ContractResources.contract();

        for (Contract.Kind kind : Contract.Kind.values()) {
            System.out.println();
            System.out.println("── " + kind.name().toLowerCase(java.util.Locale.ROOT) + " ──");

            for (Map.Entry<String, String> entry
                    : Contract.composeExpected(contract, kind).entrySet()) {
                StringBuilder path = new StringBuilder(entry.getKey());

                while (path.length() < 56) {
                    path.append(' ');
                }

                System.out.println("  " + path + entry.getValue());
            }
        }
    }
}
