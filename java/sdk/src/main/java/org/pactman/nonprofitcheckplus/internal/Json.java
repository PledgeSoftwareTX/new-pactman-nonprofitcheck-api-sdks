package org.pactman.nonprofitcheckplus.internal;

import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * A minimal JSON reader and writer.
 *
 * <p>Internal. It exists so the SDK has no runtime dependencies: adding this
 * package to an application cannot drag in a JSON library whose version
 * collides with the one the application already runs.
 *
 * <p>Decoded values are plain Java types, so nothing downstream needs to know
 * this class exists: a JSON object becomes a {@link LinkedHashMap} in the order
 * the server sent it, an array becomes an {@link ArrayList}, a string becomes a
 * {@link String}, {@code true}/{@code false} become {@link Boolean}, and
 * {@code null} stays {@code null}. Numbers become a {@link Long} when they are
 * integral and fit, and a {@link Double} otherwise — the API's counters and
 * timings are integers, and widening them all to double would print
 * {@code 1.0} where the server said {@code 1}.
 */
public final class Json {

    private Json() {
    }

    /**
     * Decodes a JSON document.
     *
     * @param text the document.
     * @return the decoded value: a map, list, string, boolean, number, or {@code null}.
     * @throws JsonException if the text is not well-formed JSON.
     */
    public static Object parse(String text) {
        if (text == null) {
            throw new JsonException("Cannot parse null as JSON.");
        }

        Parser parser = new Parser(text);
        Object value = parser.readValue();
        parser.skipWhitespace();

        if (!parser.atEnd()) {
            throw parser.error("Unexpected trailing content");
        }

        return value;
    }

    /**
     * Encodes a value as JSON.
     *
     * <p>Accepts what {@link #parse(String)} produces, plus any {@link Number},
     * {@link CharSequence}, {@link Boolean}, {@link Map} or {@link Iterable}.
     * Map keys are written with {@code toString()}.
     *
     * @param value the value to encode.
     * @return a JSON document.
     * @throws JsonException if a value has no JSON representation.
     */
    public static String write(Object value) {
        StringBuilder out = new StringBuilder();
        writeValue(value, out);

        return out.toString();
    }

    private static void writeValue(Object value, StringBuilder out) {
        if (value == null) {
            out.append("null");
        } else if (value instanceof CharSequence) {
            writeString(value.toString(), out);
        } else if (value instanceof Boolean) {
            out.append(value.toString());
        } else if (value instanceof Number) {
            writeNumber((Number) value, out);
        } else if (value instanceof Map) {
            writeObject((Map<?, ?>) value, out);
        } else if (value instanceof Iterable) {
            writeArray((Iterable<?>) value, out);
        } else if (value instanceof Object[]) {
            writeArray(java.util.Arrays.asList((Object[]) value), out);
        } else {
            throw new JsonException(
                    "No JSON representation for " + value.getClass().getName() + ".");
        }
    }

    private static void writeNumber(Number number, StringBuilder out) {
        if (number instanceof Double || number instanceof Float) {
            double raw = number.doubleValue();

            if (Double.isNaN(raw) || Double.isInfinite(raw)) {
                throw new JsonException("JSON has no representation for " + raw + ".");
            }
        }

        out.append(number.toString());
    }

    private static void writeObject(Map<?, ?> map, StringBuilder out) {
        out.append('{');
        boolean first = true;

        for (Map.Entry<?, ?> entry : map.entrySet()) {
            if (!first) {
                out.append(',');
            }

            first = false;
            writeString(String.valueOf(entry.getKey()), out);
            out.append(':');
            writeValue(entry.getValue(), out);
        }

        out.append('}');
    }

    private static void writeArray(Iterable<?> values, StringBuilder out) {
        out.append('[');
        boolean first = true;

        for (Object value : values) {
            if (!first) {
                out.append(',');
            }

            first = false;
            writeValue(value, out);
        }

        out.append(']');
    }

    private static void writeString(String value, StringBuilder out) {
        out.append('"');

        for (int i = 0; i < value.length(); i++) {
            char c = value.charAt(i);

            switch (c) {
                case '"':
                    out.append("\\\"");
                    break;
                case '\\':
                    out.append("\\\\");
                    break;
                case '\n':
                    out.append("\\n");
                    break;
                case '\r':
                    out.append("\\r");
                    break;
                case '\t':
                    out.append("\\t");
                    break;
                case '\b':
                    out.append("\\b");
                    break;
                case '\f':
                    out.append("\\f");
                    break;
                default:
                    // Control characters must be escaped; everything else, including
                    // non-ASCII, is written through as UTF-8 rather than \\u-escaped.
                    if (c < 0x20) {
                        out.append(String.format("\\u%04x", (int) c));
                    } else {
                        out.append(c);
                    }
            }
        }

        out.append('"');
    }

    /** A recursive-descent reader over one document. */
    private static final class Parser {
        private static final int MAX_DEPTH = 200;

        private final String text;
        private int position;
        private int depth;

        Parser(String text) {
            this.text = text;
        }

        Object readValue() {
            skipWhitespace();

            if (atEnd()) {
                throw error("Unexpected end of input");
            }

            char c = text.charAt(position);

            switch (c) {
                case '{':
                    return readObject();
                case '[':
                    return readArray();
                case '"':
                    return readString();
                case 't':
                    expect("true");
                    return Boolean.TRUE;
                case 'f':
                    expect("false");
                    return Boolean.FALSE;
                case 'n':
                    expect("null");
                    return null;
                default:
                    return readNumber();
            }
        }

        private Map<String, Object> readObject() {
            enter();
            position++;
            Map<String, Object> object = new LinkedHashMap<>();
            skipWhitespace();

            if (peek() == '}') {
                position++;
                depth--;
                return object;
            }

            for (;;) {
                skipWhitespace();

                if (peek() != '"') {
                    throw error("Expected a property name");
                }

                String key = readString();
                skipWhitespace();

                if (peek() != ':') {
                    throw error("Expected ':' after property name");
                }

                position++;
                // A duplicate key is legal JSON; the last one wins, which is how
                // every JSON parser this SDK's callers use would also resolve it.
                object.put(key, readValue());
                skipWhitespace();
                char next = peek();

                if (next == ',') {
                    position++;
                    continue;
                }

                if (next == '}') {
                    position++;
                    depth--;
                    return object;
                }

                throw error("Expected ',' or '}' in object");
            }
        }

        private List<Object> readArray() {
            enter();
            position++;
            List<Object> array = new ArrayList<>();
            skipWhitespace();

            if (peek() == ']') {
                position++;
                depth--;
                return array;
            }

            for (;;) {
                array.add(readValue());
                skipWhitespace();
                char next = peek();

                if (next == ',') {
                    position++;
                    continue;
                }

                if (next == ']') {
                    position++;
                    depth--;
                    return array;
                }

                throw error("Expected ',' or ']' in array");
            }
        }

        private String readString() {
            position++;
            StringBuilder value = new StringBuilder();

            for (;;) {
                if (atEnd()) {
                    throw error("Unterminated string");
                }

                char c = text.charAt(position++);

                if (c == '"') {
                    return value.toString();
                }

                if (c != '\\') {
                    if (c < 0x20) {
                        throw error("Unescaped control character in string");
                    }

                    value.append(c);
                    continue;
                }

                if (atEnd()) {
                    throw error("Unterminated escape sequence");
                }

                char escape = text.charAt(position++);

                switch (escape) {
                    case '"':
                        value.append('"');
                        break;
                    case '\\':
                        value.append('\\');
                        break;
                    case '/':
                        value.append('/');
                        break;
                    case 'b':
                        value.append('\b');
                        break;
                    case 'f':
                        value.append('\f');
                        break;
                    case 'n':
                        value.append('\n');
                        break;
                    case 'r':
                        value.append('\r');
                        break;
                    case 't':
                        value.append('\t');
                        break;
                    case 'u':
                        value.append(readUnicodeEscape());
                        break;
                    default:
                        throw error("Unsupported escape '\\" + escape + "'");
                }
            }
        }

        private char readUnicodeEscape() {
            if (position + 4 > text.length()) {
                throw error("Truncated \\u escape");
            }

            String digits = text.substring(position, position + 4);

            for (int i = 0; i < 4; i++) {
                if (Character.digit(digits.charAt(i), 16) < 0) {
                    throw error("Malformed \\u escape");
                }
            }

            position += 4;

            return (char) Integer.parseInt(digits, 16);
        }

        private Object readNumber() {
            int start = position;

            if (peek() == '-') {
                position++;
            }

            readIntegerPart();
            boolean integral = true;

            if (!atEnd() && text.charAt(position) == '.') {
                integral = false;
                position++;
                readDigits();
            }

            if (!atEnd() && (text.charAt(position) == 'e' || text.charAt(position) == 'E')) {
                integral = false;
                position++;

                if (!atEnd() && (text.charAt(position) == '+' || text.charAt(position) == '-')) {
                    position++;
                }

                readDigits();
            }

            String literal = text.substring(start, position);

            if (integral) {
                try {
                    return Long.valueOf(literal);
                } catch (NumberFormatException tooWide) {
                    // An integer beyond long, such as an oversized identifier.
                    // Keeping it as a double loses precision but keeps the whole
                    // response readable, which matters more than the digits.
                    return Double.valueOf(literal);
                }
            }

            return Double.valueOf(literal);
        }

        /**
         * The integer part, which JSON allows to be a lone {@code 0} or a
         * non-zero digit followed by any digits — but never {@code 01}. Accepting
         * a leading zero here would quietly read a malformed document as a
         * number, and the point of this parser is to notice.
         */
        private void readIntegerPart() {
            if (atEnd()) {
                throw error("Expected a digit");
            }

            if (text.charAt(position) == '0') {
                position++;

                if (!atEnd() && text.charAt(position) >= '0' && text.charAt(position) <= '9') {
                    throw error("Number has a leading zero");
                }

                return;
            }

            readDigits();
        }

        private void readDigits() {
            int start = position;

            while (!atEnd() && text.charAt(position) >= '0' && text.charAt(position) <= '9') {
                position++;
            }

            if (position == start) {
                throw error("Expected a digit");
            }
        }

        private void expect(String literal) {
            if (!text.startsWith(literal, position)) {
                throw error("Expected '" + literal + "'");
            }

            position += literal.length();
        }

        private char peek() {
            if (atEnd()) {
                throw error("Unexpected end of input");
            }

            return text.charAt(position);
        }

        private void enter() {
            depth++;

            if (depth > MAX_DEPTH) {
                // A hostile or corrupt response should surface as a parse failure,
                // not as a StackOverflowError halfway up the caller's stack.
                throw error("Nested more than " + MAX_DEPTH + " levels deep");
            }
        }

        void skipWhitespace() {
            while (!atEnd()) {
                char c = text.charAt(position);

                if (c == ' ' || c == '\t' || c == '\n' || c == '\r') {
                    position++;
                } else {
                    return;
                }
            }
        }

        boolean atEnd() {
            return position >= text.length();
        }

        JsonException error(String message) {
            return new JsonException(message + " at position " + position + ".");
        }
    }
}
