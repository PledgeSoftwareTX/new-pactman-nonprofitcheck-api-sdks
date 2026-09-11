package org.pactman.nonprofitcheckplus.devtools;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Instant;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import org.pactman.nonprofitcheckplus.PactmanClient;
import org.pactman.nonprofitcheckplus.SdkVersion;
import org.pactman.nonprofitcheckplus.config.PactmanClientOptions;
import org.pactman.nonprofitcheckplus.internal.Json;
import org.pactman.nonprofitcheckplus.models.BulkCheckResult;
import org.pactman.nonprofitcheckplus.models.SingleCheckResult;

/**
 * Checks a live deployment against what this package promises.
 *
 * <p>Two questions, answered separately because they fail for different reasons:
 *
 * <ol>
 *   <li><b>Does the API still match the contract?</b> Every value the response
 *       carries must be a form {@code response-contract.json} permits, and every
 *       field the contract requires must arrive. This is the question with a
 *       caller on the other end of it — someone wrote {@code getBmfStatus()}
 *       expecting a boolean on the strength of that promise.
 *   <li><b>Has the API moved since we last looked?</b> Held against a recorded
 *       baseline, which catches changes the contract is silent about. A baseline
 *       is one organization's response on one afternoon, so it is compared with
 *       nullability and reachability excused — see {@link Contract#baselineDiff}.
 * </ol>
 *
 * <p>This spends real quota against a real key. It is not part of {@code verify}.
 */
public final class SmokeLive {

    private SmokeLive() {
    }

    /**
     * Runs the checks.
     *
     * @param args {@code --ein <ein>}, {@code --bulk <ein,ein>},
     *             {@code --baseline <path>}, {@code --record <path>}.
     * @return the number of checks that failed.
     * @throws IOException when a baseline cannot be read or written.
     */
    public static int run(String[] args) throws IOException {
        Map<String, String> options = parse(args);
        String apiKey = System.getenv("PACTMAN_API_KEY");

        if (apiKey == null || apiKey.trim().isEmpty()) {
            System.err.println("Set PACTMAN_API_KEY to run the live smoke check.");
            return 1;
        }

        String ein = options.getOrDefault("ein", "411787097");
        List<String> bulkEins = Arrays.asList(
                options.getOrDefault("bulk", ein + ",996589560").split(","));

        PactmanClientOptions.Builder clientOptions =
                PactmanClientOptions.builder().apiKey(apiKey).timeoutMs(20_000);
        String baseUrl = System.getenv("PACTMAN_BASE_URL");

        if (baseUrl != null && !baseUrl.trim().isEmpty()) {
            clientOptions.baseUrl(baseUrl.trim());
        }

        Map<String, Object> contract = ContractResources.contract();
        int failures = 0;

        try (PactmanClient client = new PactmanClient(clientOptions.build())) {
            System.out.println("Pactman Nonprofit Check Plus — live smoke");
            System.out.println("  sdk      : " + SdkVersion.VERSION);
            System.out.println("  baseUrl  : " + client.baseUrl());
            System.out.println("  ein      : " + ein);
            System.out.println("  bulk     : " + String.join(", ", bulkEins));

            SingleCheckResult single = client.nonprofits().check(ein);
            BulkCheckResult bulk = client.nonprofits().checkBulk(bulkEins);

            Map<String, String> singleSignature = Contract.signatureOf(single.getRaw().toMap());
            Map<String, String> bulkSignature = Contract.signatureOf(bulk.getRaw().toMap());

            failures += checkAgainstContract(
                    "single", contract, Contract.Kind.SINGLE, singleSignature);
            failures += checkAgainstContract("bulk", contract, Contract.Kind.BULK, bulkSignature);

            String baselinePath = options.get("baseline");

            if (options.containsKey("record")) {
                Path target = Path.of(options.get("record"));
                writeBaseline(target, client.baseUrl(), ein, bulkEins,
                        singleSignature, bulkSignature);
                System.out.println();
                System.out.println("Recorded a baseline at " + target);
            } else if (baselinePath != null) {
                failures += checkAgainstBaseline(
                        Path.of(baselinePath), singleSignature, bulkSignature);
            } else {
                System.out.println();
                System.out.println("No baseline given; pass --baseline <path> to compare against"
                        + " one, or --record <path> to write one.");
            }
        }

        System.out.println();
        System.out.println(failures == 0
                ? "All checks passed."
                : failures + " check(s) failed.");

        return failures;
    }

    private static int checkAgainstContract(
            String label,
            Map<String, Object> contract,
            Contract.Kind kind,
            Map<String, String> observed) {
        Map<String, String> expected = Contract.composeExpected(contract, kind);
        Set<String> required = Contract.requiredPathsOf(contract, kind);

        Difference types = Contract.contractDiff(expected, observed);
        Difference coverage = Contract.coverageDiff(expected, observed, required);

        System.out.println();
        System.out.println(label + " — values match the contract: "
                + (types.clean() ? "ok" : Contract.summarize(types.changes())));

        if (!types.clean()) {
            System.out.println(Contract.formatChanges(types.changes(), "      "));
        }

        System.out.println(label + " — fields match the contract: "
                + (coverage.clean() ? "ok" : Contract.summarize(coverage.changes()))
                + "  (" + coverage.unreachable() + " unreachable, "
                + coverage.optionalAbsent() + " optional and absent)");

        if (!coverage.clean()) {
            System.out.println(Contract.formatChanges(coverage.changes(), "      "));
        }

        return (types.clean() ? 0 : 1) + (coverage.clean() ? 0 : 1);
    }

    @SuppressWarnings("unchecked")
    private static int checkAgainstBaseline(
            Path baselinePath, Map<String, String> single, Map<String, String> bulk)
            throws IOException {
        Map<String, Object> baseline = (Map<String, Object>) Json.parse(
                new String(Files.readAllBytes(baselinePath), StandardCharsets.UTF_8));

        int failures = 0;

        for (String[] pair : new String[][] {{"single", "single"}, {"bulk", "bulk"}}) {
            Map<String, String> recorded = signature(baseline, pair[1]);
            Map<String, String> observed = "single".equals(pair[0]) ? single : bulk;
            Difference diff = Contract.baselineDiff(recorded, observed);

            System.out.println();
            System.out.println(pair[0] + " — unchanged since the recording: "
                    + (diff.clean() ? "ok" : Contract.summarize(diff.changes()))
                    + "  (" + diff.nullable() + " nullability, "
                    + diff.unreachable() + " unreachable)");

            if (!diff.clean()) {
                System.out.println(Contract.formatChanges(diff.changes(), "      "));
                failures += 1;
            }
        }

        return failures;
    }

    @SuppressWarnings("unchecked")
    private static Map<String, String> signature(Map<String, Object> baseline, String kind) {
        Object recorded = baseline.get(kind);
        Map<String, String> signature = new LinkedHashMap<>();

        if (recorded instanceof Map) {
            Object paths = ((Map<String, Object>) recorded).get("signature");

            if (paths instanceof Map) {
                for (Map.Entry<String, Object> entry
                        : ((Map<String, Object>) paths).entrySet()) {
                    signature.put(entry.getKey(), String.valueOf(entry.getValue()));
                }
            }
        }

        return signature;
    }

    private static void writeBaseline(
            Path target,
            String baseUrl,
            String ein,
            List<String> bulkEins,
            Map<String, String> single,
            Map<String, String> bulk)
            throws IOException {
        Map<String, Object> baseline = new LinkedHashMap<>();
        baseline.put("note",
                "Signatures of two live responses: path, JSON type and value format, never a "
                        + "value. Held against a later run by `smoke-live` to answer whether the "
                        + "API has moved. Safe to commit — no response value is recorded.");
        baseline.put("recordedAt", Instant.now().toString());
        baseline.put("baseUrl", baseUrl);
        baseline.put("sdkVersion", SdkVersion.VERSION);

        Map<String, Object> singleEntry = new LinkedHashMap<>();
        singleEntry.put("ein", ein);
        singleEntry.put("signature", single);
        baseline.put("single", singleEntry);

        Map<String, Object> bulkEntry = new LinkedHashMap<>();
        bulkEntry.put("eins", new ArrayList<>(bulkEins));
        bulkEntry.put("signature", bulk);
        baseline.put("bulk", bulkEntry);

        Files.write(target, Json.write(baseline).getBytes(StandardCharsets.UTF_8));
    }

    private static Map<String, String> parse(String[] args) {
        Map<String, String> options = new LinkedHashMap<>();

        for (int i = 0; i < args.length; i++) {
            if (args[i].startsWith("--") && i + 1 < args.length) {
                options.put(args[i].substring(2), args[i + 1]);
                i += 1;
            }
        }

        return options;
    }
}
