package org.pactman.nonprofitcheckplus.devtools;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.Comparator;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.TreeMap;
import java.util.regex.Pattern;

/**
 * Signatures of a JSON response, and the differences between two of them.
 *
 * <p>A recorded copy of a live response is worthless as a drift detector: every
 * run returns a fresh {@code report_date}, a different {@code timeTaken} and a
 * usage counter that only goes up, so a byte comparison fails for reasons that
 * have nothing to do with the API changing. What is stable is the shape — which
 * fields exist, what type each carries, and what form its values take. That is
 * what a signature captures.
 *
 * <p>A signature is a flat, sorted map of path to type token:
 *
 * <pre>
 *   code                                              number
 *   data.ein                                          digits:9
 *   data.most_recent_bmf                              date
 *   data.organization_types[].deductibility_limitation text
 *   data.pub78_verified                               boolean
 *   errors                                            null
 * </pre>
 *
 * <p>Flat, so a field that appears, disappears or changes type is one line in a
 * diff, and so comparing two signatures is a key-by-key walk rather than a
 * recursive descent that has to re-derive structure it already knows.
 *
 * <p>The two halves are compared separately — {@link #schemaDiff} over the
 * paths, {@link #typeDiff} over the tokens — because they fail for different
 * reasons. A field that disappeared breaks callers that read it; a field that
 * changed type breaks callers that parse it. Reporting them as one number would
 * say only that something moved.
 *
 * <p>The token vocabulary:
 *
 * <pre>
 *   object, array, boolean, number, null   the JSON type, structural
 *   date            `M/D/YYYY h:mm:ss AM` — the format every API timestamp uses
 *   date:iso        an ISO-8601 timestamp, which this API does not currently send
 *   digits:9        a string of digits, grouped by length: "411787097" is
 *                   digits:9, "01085-2643" is digits:5-4, "00" is digits:2
 *   url             an http(s) URL
 *   ofac-sentence   the SDN sentence `ofac_status` carries, in either wording
 *   empty           an empty or whitespace-only string
 *   text            any other string
 * </pre>
 *
 * <p>A path that carries more than one token across a single response — a field
 * that is a date on one organization in a bulk batch and null on another —
 * records them sorted and joined by {@code |}, as in {@code date|null}.
 *
 * <p>Only shapes go in. No value from the response is ever recorded, so a
 * baseline is safe to commit and a diff is safe to print.
 */
public final class Contract {

    /** Which endpoint a signature describes. */
    public enum Kind {
        /** The single-check endpoint, whose {@code data} is one object. */
        SINGLE,
        /** The bulk endpoint, whose {@code data} is a list. */
        BULK
    }

    /** The format every timestamp in this API uses. */
    private static final Pattern API_DATE =
            Pattern.compile("^\\d{1,2}/\\d{1,2}/\\d{4},? \\d{1,2}:\\d{2}:\\d{2} ?(?:AM|PM)$",
                    Pattern.CASE_INSENSITIVE);

    private static final Pattern ISO_DATE =
            Pattern.compile("^\\d{4}-\\d{2}-\\d{2}(?:[T ]\\d{2}:\\d{2}|$)");

    /** Digits, optionally in hyphen-separated groups: EINs, ZIPs, IRS codes. */
    private static final Pattern DIGIT_GROUPS = Pattern.compile("^\\d+(?:-\\d+)*$");

    private static final Pattern URL_LIKE =
            Pattern.compile("^https?://", Pattern.CASE_INSENSITIVE);

    /**
     * The clause both OFAC wordings share.
     *
     * <p>Matching the clause rather than either whole sentence keeps a genuine
     * change of wording visible — it would fall back to {@code text} — while a
     * subject that goes from "was NOT included" to "may be included", or a
     * possible match whose UID differs, stays the same shape. That is a change
     * in the data, not the contract.
     */
    private static final Pattern OFAC_SENTENCE =
            Pattern.compile("Specially Designated Nationals ?\\(SDN\\) list",
                    Pattern.CASE_INSENSITIVE);

    /** String tokens {@code string} stands for, when the contract claims no format. */
    private static final Set<String> STRING_TOKENS = new HashSet<>(
            Arrays.asList("text", "date", "date:iso", "url", "ofac-sentence", "empty"));

    /** Removals first: a field that disappeared breaks callers that read it. */
    private static final Comparator<Change> CHANGE_ORDER =
            Comparator.<Change>comparingInt(change -> change.kind().ordinal())
                    .thenComparing(Change::path);

    private Contract() {
    }

    /** Classifies a string by the form of its value, never by the value itself. */
    public static String formatOf(String value) {
        // Newer runtimes format times with a narrow no-break space; the API
        // sends a plain one. Normalize so the same timestamp is not two tokens.
        String text = value.replace('\u00a0', ' ').replace('\u202f', ' ');

        if (text.trim().isEmpty()) {
            return "empty";
        }

        if (API_DATE.matcher(text).matches()) {
            return "date";
        }

        if (ISO_DATE.matcher(text).find()) {
            return "date:iso";
        }

        if (DIGIT_GROUPS.matcher(text).matches()) {
            StringBuilder groups = new StringBuilder("digits:");
            String[] parts = text.split("-");

            for (int i = 0; i < parts.length; i++) {
                if (i > 0) {
                    groups.append('-');
                }

                groups.append(parts[i].length());
            }

            return groups.toString();
        }

        if (URL_LIKE.matcher(text).find()) {
            return "url";
        }

        if (OFAC_SENTENCE.matcher(text).find()) {
            return "ofac-sentence";
        }

        return "text";
    }

    private static String tokenFor(Object value) {
        if (value == null) {
            return "null";
        }

        if (value instanceof List) {
            return "array";
        }

        if (value instanceof String) {
            return formatOf((String) value);
        }

        if (value instanceof Boolean) {
            return "boolean";
        }

        if (value instanceof Number) {
            return "number";
        }

        return "object";
    }

    /**
     * Builds the signature of a decoded JSON response.
     *
     * @param value the decoded response.
     * @return path to token, sorted by path.
     */
    public static Map<String, String> signatureOf(Object value) {
        Map<String, Set<String>> tokens = new TreeMap<>();
        collect(value, "", tokens);

        Map<String, String> signature = new TreeMap<>();

        for (Map.Entry<String, Set<String>> entry : tokens.entrySet()) {
            List<String> sorted = new ArrayList<>(entry.getValue());
            java.util.Collections.sort(sorted);
            signature.put(entry.getKey(), String.join("|", sorted));
        }

        return signature;
    }

    private static void collect(Object value, String path, Map<String, Set<String>> tokens) {
        if (!path.isEmpty()) {
            tokens.computeIfAbsent(path, key -> new LinkedHashSet<>()).add(tokenFor(value));
        }

        // Every element of an array contributes to one path, so a batch of ten
        // organizations describes one record shape rather than ten.
        if (value instanceof List) {
            for (Object item : (List<?>) value) {
                collect(item, path + "[]", tokens);
            }

            return;
        }

        if (value instanceof Map) {
            for (Map.Entry<?, ?> entry : ((Map<?, ?>) value).entrySet()) {
                String key = String.valueOf(entry.getKey());
                collect(entry.getValue(), path.isEmpty() ? key : path + "." + key, tokens);
            }
        }
    }

    /**
     * Fields the API stopped sending, and fields it started sending.
     *
     * <p>Additions count. A field the API added is forward-compatible for a
     * caller — the SDK surfaces it either way — but it is still the API
     * changing, and a baseline that quietly absorbs additions cannot tell you
     * when it did.
     *
     * @param baseline the earlier signature.
     * @param current  the later signature.
     * @return the differences.
     */
    public static Difference schemaDiff(
            Map<String, String> baseline, Map<String, String> current) {
        List<Change> changes = new ArrayList<>();

        for (Map.Entry<String, String> entry : baseline.entrySet()) {
            if (!current.containsKey(entry.getKey())) {
                changes.add(Change.removed(entry.getKey(), entry.getValue()));
            }
        }

        for (Map.Entry<String, String> entry : current.entrySet()) {
            if (!baseline.containsKey(entry.getKey())) {
                changes.add(Change.added(entry.getKey(), entry.getValue()));
            }
        }

        return new Difference(sorted(changes), 0, 0, 0);
    }

    /**
     * Fields whose type or value format changed, across the paths both
     * signatures have.
     *
     * <p>Paths only one of them has are {@link #schemaDiff}'s to report, so a
     * single renamed field is one failure rather than two.
     *
     * @param baseline the earlier signature.
     * @param current  the later signature.
     * @return the differences.
     */
    public static Difference typeDiff(
            Map<String, String> baseline, Map<String, String> current) {
        List<Change> changes = new ArrayList<>();

        for (Map.Entry<String, String> entry : baseline.entrySet()) {
            String now = current.get(entry.getKey());

            if (now != null && !now.equals(entry.getValue())) {
                changes.add(Change.changed(entry.getKey(), entry.getValue(), now));
            }
        }

        return new Difference(sorted(changes), 0, 0, 0);
    }

    /**
     * A recording held against a live response, with the differences a recording
     * cannot speak to left out.
     *
     * <p>A baseline is one organization's response on one afternoon, so much of
     * what separates it from today's run is not the API moving — it is a
     * different subject, or the same subject whose Publication 78 row lapsed
     * since. Two kinds of difference fall out of that, and neither is drift.
     *
     * <p><b>Nullability.</b> {@code pub78_city} was {@code text} when the
     * recording was made and is {@code null} now. The field is still there and
     * still nullable; this organization simply has no Publication 78 city. Only
     * a move between two forms a value actually took — {@code digits:9} to
     * {@code text} — says the API changed.
     *
     * <p><b>Reachability.</b> {@code organization_types} arrived null, so the
     * paths beneath it had nowhere to be and read as removed. Which side has the
     * populated parent is an accident of which ran first.
     *
     * <p>Both are counted rather than dropped, so a green run still says how
     * much it passed over.
     *
     * @param before  the recorded signature.
     * @param current the live signature.
     * @return the differences, with the excused counts.
     */
    public static Difference baselineDiff(
            Map<String, String> before, Map<String, String> current) {
        List<Change> changes = new ArrayList<>();
        int nullable = 0;
        int unreachable = 0;

        for (Map.Entry<String, String> entry : before.entrySet()) {
            String path = entry.getKey();
            String token = entry.getValue();

            if (current.containsKey(path)) {
                String now = current.get(path);

                if (now.equals(token)) {
                    continue;
                }

                if (nullabilityOnly(token, now)) {
                    nullable += 1;
                    continue;
                }

                changes.add(Change.changed(path, token, now));
                continue;
            }

            if (unreachableIn(path, current)) {
                unreachable += 1;
                continue;
            }

            changes.add(Change.removed(path, token));
        }

        for (Map.Entry<String, String> entry : current.entrySet()) {
            if (before.containsKey(entry.getKey())) {
                continue;
            }

            if (unreachableIn(entry.getKey(), before)) {
                unreachable += 1;
                continue;
            }

            changes.add(Change.added(entry.getKey(), entry.getValue()));
        }

        return new Difference(sorted(changes), nullable, unreachable, 0);
    }

    /**
     * Whether two tokens differ only over whether a value arrived.
     *
     * <p>Drop {@code null} from both sides and compare what is left.
     * {@code date} against {@code date|null} leaves the same form on each.
     * {@code date} against {@code null} leaves one side with nothing, and a side
     * that recorded no form makes no claim about the form — so there is nothing
     * there to have moved. {@code digits:9} against {@code text} leaves two
     * different forms, which is drift and stays reported.
     */
    private static boolean nullabilityOnly(String before, String after) {
        List<String> left = withoutNull(before);
        List<String> right = withoutNull(after);

        return left.isEmpty() || right.isEmpty() || left.equals(right);
    }

    private static List<String> withoutNull(String token) {
        List<String> forms = new ArrayList<>();

        for (String one : token.split("\\|")) {
            if (!"null".equals(one)) {
                forms.add(one);
            }
        }

        return forms;
    }

    /**
     * Whether an observed token is one the contract allows.
     *
     * <p>{@code string} is a wildcard over every string token, because a
     * declared string makes no claim about the form of the value. Where the
     * contract does make one — an EIN is nine digits, a timestamp is
     * {@code M/D/YYYY h:mm:ss AM} — it names that token instead, and a value
     * that stops matching fails even though it is still, technically, a string.
     * That is the point: a timestamp that turns ISO breaks every caller parsing
     * it, and a declared type never notices.
     *
     * @param allowed the contract's token expression.
     * @param token   one observed token.
     * @return whether the contract permits it.
     */
    public static boolean permits(String allowed, String token) {
        List<String> tokens = Arrays.asList(allowed.split("\\|"));

        return tokens.contains(token)
                || (tokens.contains("string") && isStringToken(token));
    }

    private static boolean isStringToken(String token) {
        return STRING_TOKENS.contains(token) || token.startsWith("digits:");
    }

    /**
     * The flat expected signature for one endpoint, built from the shared parts.
     *
     * <p>The record is described once and used for both endpoints, so single and
     * bulk cannot drift apart in the contract the way they can on the wire —
     * where {@code bmf_status} could arrive as a string from one and a boolean
     * from the other. One description means one of those two has to be reported
     * as wrong.
     *
     * @param contract the parsed {@code response-contract.json}.
     * @param kind     which endpoint.
     * @return path to token, sorted by path.
     */
    public static Map<String, String> composeExpected(Map<String, Object> contract, Kind kind) {
        boolean single = kind == Kind.SINGLE;
        String prefix = single ? "data." : "data[].";
        Map<String, String> expected = new TreeMap<>();

        expected.putAll(section(contract, "envelope"));
        expected.put("data", single ? "null|object" : "array|null");
        expected.put("errors[]", "object");
        expected.put("errors[].eins[]", "string");

        for (Map.Entry<String, String> field : section(contract, "errorDetail").entrySet()) {
            expected.put("errors[]." + field.getKey(), field.getValue());
        }

        if (!single) {
            expected.put("data[]", "object");
        }

        for (Map.Entry<String, String> field : section(contract, "nonprofit").entrySet()) {
            expected.put(prefix + field.getKey(), field.getValue());
        }

        // Nullable elements, not just a nullable array: the API sends a null in
        // the list where Publication 78 has a deductibility row it cannot
        // resolve, so a caller reading the first entry has to check.
        expected.put(prefix + "organization_types[]", "null|object");

        for (Map.Entry<String, String> field : section(contract, "organizationType").entrySet()) {
            expected.put(prefix + "organization_types[]." + field.getKey(), field.getValue());
        }

        return expected;
    }

    /**
     * Paths where the live response carries a value the contract permits no form of.
     *
     * <p>Paths the contract has never heard of are {@link #coverageDiff}'s to
     * report, so a field the API invented is one failure rather than two.
     *
     * @param expected the composed contract signature.
     * @param observed the live signature.
     * @return the differences.
     */
    public static Difference contractDiff(
            Map<String, String> expected, Map<String, String> observed) {
        List<Change> changes = new ArrayList<>();

        for (Map.Entry<String, String> entry : observed.entrySet()) {
            String allowed = expected.get(entry.getKey());

            if (allowed == null) {
                continue;
            }

            List<String> offending = new ArrayList<>();

            for (String token : entry.getValue().split("\\|")) {
                if (!permits(allowed, token)) {
                    offending.add(token);
                }
            }

            if (!offending.isEmpty()) {
                changes.add(Change.changed(
                        entry.getKey(), allowed, String.join("|", offending)));
            }
        }

        return new Difference(sorted(changes), 0, 0, 0);
    }

    /**
     * Fields the API sent that the contract does not predict, and fields it
     * predicts that the API did not send.
     *
     * <p>Both directions fail. An unpredicted field is readable only by a caller
     * who already knows to look, and a predicted field that stopped arriving
     * breaks every caller that reads it. The typed accessors notice neither, so
     * this is the only place either one is caught.
     *
     * <p>The exception is a path that had nowhere to arrive:
     * {@code errors[].reason} while {@code errors} is null, or a member of
     * {@code organization_types[]} while that array is null or empty. The parent
     * already accounts for the child's absence, and every successful response
     * has a null {@code errors} — reporting those would fail every green run and
     * say nothing.
     *
     * <p>A container that vanished is reported once, at its shallowest path: a
     * {@code data} that stopped arriving is one failure, not fifty-nine.
     *
     * @param expected the composed contract signature.
     * @param observed the live signature.
     * @param required paths a response must carry, or {@code null} to treat
     *                 every predicted path as required.
     * @return the differences, with the excused counts.
     */
    public static Difference coverageDiff(
            Map<String, String> expected, Map<String, String> observed, Set<String> required) {
        List<Change> changes = new ArrayList<>();
        int unreachable = 0;
        int optionalAbsent = 0;

        for (Map.Entry<String, String> entry : observed.entrySet()) {
            if (!expected.containsKey(entry.getKey())) {
                changes.add(Change.added(entry.getKey(), entry.getValue()));
            }
        }

        Set<String> missing = new LinkedHashSet<>();

        for (String path : expected.keySet()) {
            if (!observed.containsKey(path)) {
                missing.add(path);
            }
        }

        for (String path : missing) {
            if (unreachableIn(path, observed)) {
                unreachable += 1;
                continue;
            }

            boolean underMissingParent = false;

            for (String ancestor : ancestorsOf(path)) {
                if (missing.contains(ancestor)) {
                    underMissingParent = true;
                    break;
                }
            }

            if (underMissingParent) {
                continue;
            }

            // A field nothing promises is present may be absent. Reporting it
            // would fail a response the SDK's own accessors accept.
            if (required != null && !required.contains(path)) {
                optionalAbsent += 1;
                continue;
            }

            changes.add(Change.removed(path, expected.get(path)));
        }

        return new Difference(sorted(changes), 0, unreachable, optionalAbsent);
    }

    /**
     * The paths a response must carry: the structural ones every envelope has,
     * and whatever the contract lists as required.
     *
     * @param contract the parsed {@code response-contract.json}.
     * @param kind     which endpoint.
     * @return the required paths.
     */
    public static Set<String> requiredPathsOf(Map<String, Object> contract, Kind kind) {
        boolean single = kind == Kind.SINGLE;
        String prefix = single ? "data." : "data[].";

        // The shape of the envelope itself, which is not optional in any response.
        Set<String> paths = new LinkedHashSet<>(Arrays.asList(
                "data", "errors[]", "errors[].eins[]", prefix + "organization_types[]"));

        if (!single) {
            paths.add("data[]");
        }

        for (String field : requiredSection(contract, "envelope")) {
            paths.add(field);
        }

        for (String field : requiredSection(contract, "errorDetail")) {
            paths.add("errors[]." + field);
        }

        for (String field : requiredSection(contract, "nonprofit")) {
            paths.add(prefix + field);
        }

        for (String field : requiredSection(contract, "organizationType")) {
            paths.add(prefix + "organization_types[]." + field);
        }

        return paths;
    }

    /**
     * "2 removed, 1 added" — the counts that are not zero.
     *
     * @param changes the differences.
     * @return a one-line summary.
     */
    public static String summarize(List<Change> changes) {
        int[] counts = new int[Change.Kind.values().length];

        for (Change change : changes) {
            counts[change.kind().ordinal()] += 1;
        }

        List<String> parts = new ArrayList<>();

        for (Change.Kind kind : Change.Kind.values()) {
            if (counts[kind.ordinal()] > 0) {
                parts.add(counts[kind.ordinal()] + " "
                        + kind.name().toLowerCase(java.util.Locale.ROOT));
            }
        }

        return parts.isEmpty() ? "no differences" : String.join(", ", parts);
    }

    /**
     * One line per change, indented to sit under a check's own line.
     *
     * <p>Every change, with nothing elided. A run that says a field moved and
     * then hides which one sends you back to the deployment to find out by hand,
     * and the list is only long when something large moved — which is exactly
     * when the whole of it is what you need.
     *
     * @param changes the differences.
     * @param indent  the leading whitespace for each line.
     * @return the formatted lines.
     */
    public static String formatChanges(List<Change> changes, String indent) {
        StringBuilder text = new StringBuilder();

        for (Change change : changes) {
            if (text.length() > 0) {
                text.append('\n');
            }

            text.append(indent).append(change);
        }

        return text.toString();
    }

    /**
     * Every enclosing path of a signature path, innermost first.
     *
     * <pre>
     *   data.organization_types[].organization_type
     *     → data.organization_types[], data.organization_types, data
     * </pre>
     */
    private static List<String> ancestorsOf(String path) {
        List<String> ancestors = new ArrayList<>();
        String rest = path;

        for (;;) {
            if (rest.endsWith("[]")) {
                rest = rest.substring(0, rest.length() - 2);
            } else {
                int dot = rest.lastIndexOf('.');

                if (dot == -1) {
                    return ancestors;
                }

                rest = rest.substring(0, dot);
            }

            ancestors.add(rest);
        }
    }

    /**
     * Whether a container above this path arrived in a form with no room for it.
     *
     * <p>A null has no members and an empty array has no elements, so nothing
     * under either was ever going to appear.
     */
    private static boolean unreachableIn(String path, Map<String, String> observed) {
        for (String ancestor : ancestorsOf(path)) {
            String token = observed.get(ancestor);

            if (token == null) {
                continue;
            }

            List<String> tokens = Arrays.asList(token.split("\\|"));
            boolean allNull = true;

            for (String one : tokens) {
                if (!"null".equals(one)) {
                    allNull = false;
                    break;
                }
            }

            if (allNull) {
                return true;
            }

            if (tokens.contains("array") && !observed.containsKey(ancestor + "[]")) {
                return true;
            }
        }

        return false;
    }

    @SuppressWarnings("unchecked")
    private static Map<String, String> section(Map<String, Object> contract, String name) {
        Object value = contract.get(name);
        Map<String, String> fields = new LinkedHashMap<>();

        if (value instanceof Map) {
            for (Map.Entry<String, Object> entry : ((Map<String, Object>) value).entrySet()) {
                fields.put(entry.getKey(), String.valueOf(entry.getValue()));
            }
        }

        return fields;
    }

    @SuppressWarnings("unchecked")
    private static List<String> requiredSection(Map<String, Object> contract, String name) {
        Object required = contract.get("required");
        List<String> fields = new ArrayList<>();

        if (required instanceof Map) {
            Object listed = ((Map<String, Object>) required).get(name);

            if (listed instanceof List) {
                for (Object entry : (List<?>) listed) {
                    fields.add(String.valueOf(entry));
                }
            }
        }

        return fields;
    }

    private static List<Change> sorted(List<Change> changes) {
        List<Change> ordered = new ArrayList<>(changes);
        ordered.sort(CHANGE_ORDER);

        return ordered;
    }
}
