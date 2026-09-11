package org.pactman.nonprofitcheckplus;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertInstanceOf;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.util.Arrays;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import org.pactman.nonprofitcheckplus.internal.Json;
import org.pactman.nonprofitcheckplus.internal.JsonException;

/**
 * The JSON codec is the one piece of this SDK with no counterpart in the other
 * languages — they have a codec in the standard library and this one does not.
 * It is therefore tested on its own terms, not only through the client.
 */
class JsonTest {

    @SuppressWarnings("unchecked")
    private static Map<String, Object> object(String text) {
        return (Map<String, Object>) Json.parse(text);
    }

    @Test
    @DisplayName("decodes each JSON type to the plain Java type callers expect")
    void decodesEachType() {
        Map<String, Object> decoded = object(
                "{\"s\":\"text\",\"b\":true,\"n\":null,\"i\":42,\"d\":1.5,\"a\":[1,2],"
                        + "\"o\":{\"k\":\"v\"}}");

        assertEquals("text", decoded.get("s"));
        assertEquals(Boolean.TRUE, decoded.get("b"));
        assertNull(decoded.get("n"));
        assertEquals(Long.valueOf(42), decoded.get("i"));
        assertEquals(Double.valueOf(1.5), decoded.get("d"));
        assertEquals(Arrays.asList(1L, 2L), decoded.get("a"));
        assertInstanceOf(Map.class, decoded.get("o"));
    }

    @Test
    @DisplayName("keeps an integer an integer, so a count does not print as 1.0")
    void keepsIntegersIntegral() {
        assertEquals(Long.valueOf(1), object("{\"c\":1}").get("c"));
        assertEquals("{\"c\":1}", Json.write(object("{\"c\":1}")));
    }

    @Test
    @DisplayName("preserves field order, so a re-serialized response reads as it arrived")
    void preservesFieldOrder() {
        String text = "{\"z\":1,\"a\":2,\"m\":3}";

        assertEquals(text, Json.write(Json.parse(text)));
    }

    @Test
    @DisplayName("distinguishes an absent key from one whose value is null")
    void distinguishesAbsentFromNull() {
        Map<String, Object> decoded = object("{\"present\":null}");

        assertTrue(decoded.containsKey("present"));
        assertNull(decoded.get("present"));
        assertTrue(!decoded.containsKey("absent"));
    }

    @Test
    @DisplayName("reads every string escape, including surrogate pairs")
    void readsEscapes() {
        assertEquals(
                "quote\" slash\\ solidus/ newline\n tab\t \u00e9 \ud83c\udf89",
                Json.parse(
                        "\"quote\\\" slash\\\\ solidus\\/ newline\\n tab\\t \\u00e9 "
                                + "\\ud83c\\udf89\""));
    }

    @Test
    @DisplayName("round-trips text that needs escaping on the way out")
    void roundTripsEscapedText() {
        String awkward = "line\nbreak \"quoted\" back\\slash \u0001 control";

        assertEquals(awkward, Json.parse(Json.write(awkward)));
    }

    @Test
    @DisplayName("writes non-ASCII as UTF-8 rather than escaping it")
    void writesNonAsciiDirectly() {
        assertEquals("\"caf\u00e9\"", Json.write("caf\u00e9"));
    }

    @ParameterizedTest
    @ValueSource(strings = {
        "{", "{\"a\"}", "{\"a\":}", "[1,]", "[1 2]", "tru", "\"unterminated",
        "{\"a\":1}trailing", "01", "--1", "{\"a\":1,}", "\"\\q\"", "\"\\u00g0\"",
    })
    @DisplayName("rejects malformed documents rather than guessing")
    void rejectsMalformed(String text) {
        assertThrows(JsonException.class, () -> Json.parse(text));
    }

    @Test
    @DisplayName("refuses a document nested deeply enough to overflow the stack")
    void refusesDeepNesting() {
        StringBuilder deep = new StringBuilder();

        for (int i = 0; i < 5000; i++) {
            deep.append('[');
        }

        assertThrows(JsonException.class, () -> Json.parse(deep.toString()));
    }

    @Test
    @DisplayName("takes the last value when a document repeats a key")
    void lastDuplicateKeyWins() {
        assertEquals("second", object("{\"a\":\"first\",\"a\":\"second\"}").get("a"));
    }

    @Test
    @DisplayName("reads numbers in exponent form")
    void readsExponents() {
        assertEquals(Double.valueOf(1500.0), Json.parse("1.5e3"));
        assertEquals(Double.valueOf(-0.25), Json.parse("-2.5E-1"));
    }

    @Test
    @DisplayName("ignores whitespace between tokens")
    void ignoresWhitespace() {
        assertEquals(
                Arrays.asList(1L, 2L), Json.parse("  [\n  1 ,\t 2\r\n ]  "));
    }

    @Test
    @DisplayName("writes an array of strings as the bulk endpoint expects")
    void writesBulkPayload() {
        List<String> eins = Arrays.asList("411787097", "996589560");

        assertEquals("[\"411787097\",\"996589560\"]", Json.write(eins));
    }

    @Test
    @DisplayName("refuses to write a value JSON cannot represent")
    void refusesUnrepresentableValues() {
        Map<String, Object> broken = new LinkedHashMap<>();
        broken.put("when", new Object());

        assertThrows(JsonException.class, () -> Json.write(broken));
        assertThrows(JsonException.class, () -> Json.write(Double.NaN));
        assertThrows(JsonException.class, () -> Json.write(Double.POSITIVE_INFINITY));
    }

    @Test
    @DisplayName("writes an empty object and an empty array")
    void writesEmptyContainers() {
        assertEquals("{}", Json.write(new LinkedHashMap<String, Object>()));
        assertEquals("[]", Json.write(java.util.Collections.emptyList()));
        assertEquals(new LinkedHashMap<String, Object>(), Json.parse("{}"));
        assertEquals(java.util.Collections.emptyList(), Json.parse("[]"));
    }
}
