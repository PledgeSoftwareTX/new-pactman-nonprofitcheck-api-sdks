package org.pactman.nonprofitcheckplus.examples;

import java.io.IOException;
import java.util.Arrays;
import org.pactman.nonprofitcheckplus.devtools.FixtureApi;
import org.pactman.nonprofitcheckplus.examples.support.Catalog;
import org.pactman.nonprofitcheckplus.examples.support.Example;
import org.pactman.nonprofitcheckplus.examples.support.ExampleFailedException;

/**
 * Runs the examples.
 *
 * <pre>
 *   --list              every example and what it demonstrates
 *   &lt;id&gt; [args...]      one example, such as `ex-01`
 *   --smoke             every example against one shared fixture API
 * </pre>
 *
 * <p>{@code --smoke} is what CI runs. It needs no key and no network: one
 * fixture server is started, every example is pointed at it, and an example that
 * did not get the outcome it was demonstrating fails the run.
 */
public final class Main {

    private Main() {
    }

    /**
     * Entry point.
     *
     * @param args the command line.
     * @throws IOException when the fixture API cannot be started.
     */
    public static void main(String[] args) throws IOException {
        if (args.length == 0 || "--list".equals(args[0]) || "-l".equals(args[0])) {
            list();
            return;
        }

        if ("--smoke".equals(args[0])) {
            smoke();
            return;
        }

        Example example = Catalog.byId(args[0]);

        if (example == null) {
            System.err.println("No example called \"" + args[0] + "\".");
            System.err.println();
            list();

            throw new ExampleFailedException("No example called \"" + args[0] + "\".");
        }

        try {
            example.run(Arrays.copyOfRange(args, 1, args.length));
        } catch (Exception failure) {
            throw new ExampleFailedException(example.id() + " failed: " + failure);
        }
    }

    private static void list() {
        System.out.println("Pactman Nonprofit Check Plus — examples");
        System.out.println();

        for (Example example : Catalog.all()) {
            StringBuilder id = new StringBuilder(example.id());

            while (id.length() < 12) {
                id.append(' ');
            }

            System.out.println("  " + id + example.title());
        }

        System.out.println();
        System.out.println("Run one:  mvn -q -pl examples exec:java -Dexec.args=\"ex-01\"");
        System.out.println("Run all:  mvn -q -pl examples exec:java -Dexec.args=\"--smoke\"");
    }

    /**
     * Runs every example against one shared fixture API.
     *
     * <p>Fails by throwing rather than by calling {@code System.exit}: under
     * {@code exec:java} this runs inside Maven's own JVM, and exiting it would
     * end the build wherever it had got to instead of failing this step.
     */
    private static void smoke() throws IOException {
        String apiKey = "smoke-key";

        try (FixtureApi fixtures = FixtureApi.start(apiKey)) {
            // Every example reads these before falling back to the environment,
            // so one server serves all of them rather than thirty starting their
            // own.
            System.setProperty("pactman.apiKey", apiKey);
            System.setProperty("pactman.baseUrl", fixtures.baseUrl());

            int failed = 0;

            for (Example example : Catalog.all()) {
                System.out.println();
                System.out.println(
                        "══════════ " + example.id() + " — " + example.title() + " ══════════");

                try {
                    example.run(new String[0]);
                } catch (Exception | AssertionError failure) {
                    failed += 1;
                    System.out.println();
                    System.out.println("FAILED: " + failure);
                    failure.printStackTrace(System.out);
                }
            }

            System.out.println();
            System.out.println("══════════ smoke summary ══════════");
            System.out.println("  examples : " + Catalog.all().size());
            System.out.println("  failed   : " + failed);

            if (failed > 0) {
                throw new ExampleFailedException(
                        failed + " of " + Catalog.all().size() + " examples failed.");
            }
        }
    }
}
