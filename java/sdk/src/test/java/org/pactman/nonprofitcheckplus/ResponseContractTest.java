package org.pactman.nonprofitcheckplus;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.io.IOException;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.lang.reflect.InvocationTargetException;
import java.lang.reflect.Method;
import java.lang.reflect.Modifier;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collection;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.TreeSet;
import java.util.stream.Collectors;
import java.util.stream.Stream;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.MethodSource;
import org.pactman.nonprofitcheckplus.internal.Json;
import org.pactman.nonprofitcheckplus.models.ApiErrorDetail;
import org.pactman.nonprofitcheckplus.models.DataObject;
import org.pactman.nonprofitcheckplus.models.Nonprofit;
import org.pactman.nonprofitcheckplus.models.OrganizationType;
import org.pactman.nonprofitcheckplus.models.ResponseBody;

/**
 * Holds {@code response-contract.json} and the typed model in sync.
 *
 * <p>The contract is what this package promises each response looks like. The
 * typed accessors are what an IDE tells a developer to expect. A field in one
 * and not the other is drift, and drift is how an SDK starts lying about the API.
 *
 * <p>Rather than re-deriving wire names from method names — a mapping that would
 * itself need testing — these tests feed the model a sentinel response built
 * from the contract and watch which accessors light up. Removing one contract
 * field must darken exactly one accessor, which pins the mapping in both
 * directions without naming it twice.
 *
 * <p>One half of the Node SDK's version of this check has no Java counterpart:
 * TypeScript encodes nullability in the type, so it can assert that the contract
 * marks a field nullable exactly when the declared type does. Every accessor
 * here returns a reference type and may return {@code null} for a field the API
 * omitted, so there is nothing to hold the {@code null} tokens against. They are
 * checked against a live deployment by the smoke tool instead.
 */
class ResponseContractTest {

    private static final String SENTINEL = "sentinel";

    /**
     * Holds both an object and a string, so it satisfies the accessors that read
     * a list of records ({@code organization_types}) and the one that reads a
     * list of strings ({@code eins}) from the same token.
     */
    private static final List<Object> ARRAY_SENTINEL = Arrays.asList(
            java.util.Collections.singletonMap("organization_type", SENTINEL), SENTINEL);

    private static final Set<String> STRING_TOKENS = new HashSet<>(
            Arrays.asList("string", "text", "date", "date:iso", "url", "ofac-sentence", "empty"));

    private static final Map<String, Object> CONTRACT = loadContract();

    /**
     * The envelope's payload slot. Each endpoint fills it with a different
     * shape, so the contract supplies it at composition rather than declaring it
     * once here — and the accessor that reads it has no contract field to match.
     */
    private static final Set<String> UNPREDICTED_ACCESSORS =
            new HashSet<>(Arrays.asList("ResponseBody.getData"));

    @SuppressWarnings("unchecked")
    private static Map<String, Object> loadContract() {
        try (InputStream stream = ResponseContractTest.class.getResourceAsStream(
                "/org/pactman/nonprofitcheckplus/response-contract.json")) {
            StringBuilder text = new StringBuilder();
            char[] buffer = new char[8192];

            try (InputStreamReader reader =
                    new InputStreamReader(stream, StandardCharsets.UTF_8)) {
                int read;

                while ((read = reader.read(buffer)) != -1) {
                    text.append(buffer, 0, read);
                }
            }

            return (Map<String, Object>) Json.parse(text.toString());
        } catch (IOException unreadable) {
            throw new IllegalStateException("response-contract.json is not readable", unreadable);
        }
    }

    @SuppressWarnings("unchecked")
    private static Map<String, Object> section(String name) {
        Object value = CONTRACT.get(name);
        assertTrue(value instanceof Map, "the contract declares no `" + name + "` section");

        return (Map<String, Object>) value;
    }

    /** The four shapes the contract predicts, and the class that reads each. */
    static Stream<Object[]> shapes() {
        return Stream.of(
                new Object[] {"nonprofit", Nonprofit.class},
                new Object[] {"envelope", ResponseBody.class},
                new Object[] {"errorDetail", ApiErrorDetail.class},
                new Object[] {"organizationType", OrganizationType.class});
    }

    /** Accessors declared by the model itself, not inherited from {@link DataObject}. */
    private static List<Method> typedAccessors(Class<?> model) {
        List<Method> accessors = new ArrayList<>();

        for (Method method : model.getDeclaredMethods()) {
            if (!Modifier.isPublic(method.getModifiers())
                    || Modifier.isStatic(method.getModifiers())
                    || method.getParameterCount() != 0
                    || !method.getName().startsWith("get")
                    || UNPREDICTED_ACCESSORS.contains(
                            model.getSimpleName() + "." + method.getName())) {
                continue;
            }

            accessors.add(method);
        }

        accessors.sort((left, right) -> left.getName().compareTo(right.getName()));

        return accessors;
    }

    /** A response carrying every contract field, minus the one named. */
    private static DataObject sentinelFor(String shape, Class<?> model, String without) {
        Map<String, Object> fields = new LinkedHashMap<>();

        for (Map.Entry<String, Object> field : section(shape).entrySet()) {
            if (field.getKey().equals(without)) {
                continue;
            }

            fields.put(field.getKey(), sentinelValue((String) field.getValue()));
        }

        return build(model, fields);
    }

    /** A response carrying every contract field, with one field's value replaced. */
    private static DataObject sentinelWith(
            String shape, Class<?> model, String field, Object value) {
        Map<String, Object> fields = new LinkedHashMap<>();

        for (Map.Entry<String, Object> entry : section(shape).entrySet()) {
            fields.put(
                    entry.getKey(),
                    entry.getKey().equals(field)
                            ? value
                            : sentinelValue((String) entry.getValue()));
        }

        return build(model, fields);
    }

    private static DataObject build(Class<?> model, Map<String, Object> fields) {
        if (model == Nonprofit.class) {
            return new Nonprofit(fields);
        }

        if (model == ResponseBody.class) {
            return new ResponseBody(fields);
        }

        if (model == ApiErrorDetail.class) {
            return new ApiErrorDetail(fields);
        }

        return new OrganizationType(fields);
    }

    private static Object sentinelValue(String tokens) {
        if (tokens.contains("boolean")) {
            return Boolean.TRUE;
        }

        if (tokens.contains("array")) {
            return ARRAY_SENTINEL;
        }

        if (tokens.contains("number")) {
            return 1L;
        }

        return SENTINEL;
    }

    private static boolean isSet(Method accessor, Object target) {
        Object value;

        try {
            value = accessor.invoke(target);
        } catch (IllegalAccessException | InvocationTargetException unreachable) {
            throw new IllegalStateException("could not read " + accessor.getName(), unreachable);
        }

        if (value == null) {
            return false;
        }

        if (value instanceof Collection) {
            return !((Collection<?>) value).isEmpty();
        }

        return true;
    }

    private static Set<String> litAccessors(String shape, Class<?> model, String without) {
        DataObject response = sentinelFor(shape, model, without);

        return typedAccessors(model).stream()
                .filter(accessor -> isSet(accessor, response))
                .map(Method::getName)
                .collect(Collectors.toCollection(TreeSet::new));
    }

    @ParameterizedTest(name = "{0}")
    @MethodSource("shapes")
    @DisplayName("every contract field is read by exactly one typed accessor")
    void everyContractFieldIsRead(String shape, Class<?> model) {
        Set<String> all = litAccessors(shape, model, null);

        assertEquals(
                typedAccessors(model).stream().map(Method::getName)
                        .collect(Collectors.toCollection(TreeSet::new)),
                all,
                shape + ": an accessor stayed dark for a response carrying every contract field, "
                        + "so it reads a field the contract does not predict");

        for (String field : section(shape).keySet()) {
            Set<String> withoutField = litAccessors(shape, model, field);
            Set<String> darkened = new TreeSet<>(all);
            darkened.removeAll(withoutField);

            assertEquals(
                    1,
                    darkened.size(),
                    shape + "." + field + " should darken exactly one accessor, darkened "
                            + darkened);
        }
    }

    @ParameterizedTest(name = "{0}")
    @MethodSource("shapes")
    @DisplayName("the model declares no accessor the contract does not predict")
    void noUnpredictedAccessors(String shape, Class<?> model) {
        assertEquals(
                section(shape).size(),
                typedAccessors(model).size(),
                shape + ": the contract predicts " + section(shape).size() + " fields but "
                        + model.getSimpleName() + " declares " + typedAccessors(model).size()
                        + " accessors");
    }

    @ParameterizedTest(name = "{0}")
    @MethodSource("shapes")
    @DisplayName("every shape a token predicts is one the accessor can actually read")
    void everyPredictedShapeIsReadable(String shape, Class<?> model) {
        Map<String, Method> byField = accessorsByField(shape, model);

        for (Map.Entry<String, Object> field : section(shape).entrySet()) {
            String name = field.getKey();
            Method accessor = byField.get(name);

            for (String token : ((String) field.getValue()).split("\\|")) {
                DataObject response = sentinelWith(shape, model, name, valueForToken(token));

                if ("null".equals(token)) {
                    assertTrue(
                            response.has(name),
                            shape + "." + name + " returned as null should still read as present");
                    assertFalse(
                            isSet(accessor, response),
                            shape + "." + name + " is null, so " + accessor.getName()
                                    + " should report nothing");
                    continue;
                }

                assertTrue(
                        isSet(accessor, response),
                        shape + "." + name + " predicts a `" + token + "` value, but "
                                + accessor.getName() + " reads nothing from one");
            }
        }
    }

    @Test
    @DisplayName("the contract uses only tokens the smoke tool understands")
    void tokensComeFromTheSharedVocabulary() {
        Set<String> known = new HashSet<>(STRING_TOKENS);
        known.addAll(Arrays.asList("null", "boolean", "number", "array", "object"));

        for (Object[] shape : shapes().collect(Collectors.toList())) {
            for (Map.Entry<String, Object> field : section((String) shape[0]).entrySet()) {
                for (String token : ((String) field.getValue()).split("\\|")) {
                    assertTrue(
                            known.contains(token) || token.startsWith("digits:"),
                            shape[0] + "." + field.getKey() + " uses unknown token `" + token + "`");
                }
            }
        }
    }

    @Test
    @DisplayName("the contract promises no field is always present")
    void nothingIsRequired() {
        // Every accessor returns null for a field the API omitted, so this SDK
        // makes no presence promise at all. An entry here would be a promise the
        // types cannot keep.
        Map<String, Object> required = section("required");

        for (Map.Entry<String, Object> entry : required.entrySet()) {
            assertTrue(
                    entry.getValue() instanceof List && ((List<?>) entry.getValue()).isEmpty(),
                    "required." + entry.getKey() + " should be empty");
        }

        for (Object[] shape : shapes().collect(Collectors.toList())) {
            assertTrue(
                    required.containsKey((String) shape[0]),
                    "required has no entry for " + shape[0]);
        }
    }

    @Test
    @DisplayName("the contract predicts no value, only shapes")
    void predictsShapesNotValues() {
        for (Object[] shape : shapes().collect(Collectors.toList())) {
            for (Map.Entry<String, Object> field : section((String) shape[0]).entrySet()) {
                String tokens = (String) field.getValue();

                assertFalse(
                        tokens.contains("411787097") || tokens.contains("EXAMPLE"),
                        shape[0] + "." + field.getKey() + " looks like a value, not a shape");
            }
        }
    }

    /**
     * Pairs each contract field with the accessor that reads it, by darkening
     * one field at a time — the same trick as the mapping test, reused so this
     * file names no wire-field-to-method mapping of its own.
     */
    private static Map<String, Method> accessorsByField(String shape, Class<?> model) {
        Set<String> all = litAccessors(shape, model, null);
        Map<String, Method> byField = new LinkedHashMap<>();

        for (String field : section(shape).keySet()) {
            Set<String> darkened = new TreeSet<>(all);
            darkened.removeAll(litAccessors(shape, model, field));

            String name = darkened.iterator().next();

            for (Method accessor : typedAccessors(model)) {
                if (accessor.getName().equals(name)) {
                    byField.put(field, accessor);
                    break;
                }
            }
        }

        return byField;
    }

    /**
     * A value of the JSON kind a token predicts.
     *
     * <p>Deliberately a shape and not a realistic value: the contract predicts
     * shapes, and a test that fed it real EINs would start passing for the wrong
     * reason the day an accessor began parsing them.
     */
    private static Object valueForToken(String token) {
        switch (token) {
            case "null":
                return null;
            case "boolean":
                return Boolean.TRUE;
            case "number":
                return 1L;
            case "array":
                return ARRAY_SENTINEL;
            case "object":
                return java.util.Collections.singletonMap("field", SENTINEL);
            case "empty":
                return "";
            default:
                return SENTINEL;
        }
    }
}
