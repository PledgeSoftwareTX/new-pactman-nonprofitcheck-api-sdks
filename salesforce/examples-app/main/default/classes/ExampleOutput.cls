/**
 * Console formatting for the examples, written to the debug log.
 *
 * The important rule here is {@link render}: a field the API returned as `null`
 * and a field the API did not return at all print differently. Collapsing them
 * into `''` or `'-'` is how a missing value quietly becomes a match — a record
 * with no OFAC field and a record screened clean would read identically, and
 * only one of them was screened.
 */
@IsTest
public class ExampleOutput {
    /** What {@link render} prints for a field the API did not return. */
    public static final String ABSENT = '<not returned>';

    /** Prints a section heading. */
    public static void heading(String text) {
        String rule = '';

        for (Integer index = 0; index < text.length(); index++) {
            rule += '-';
        }

        System.debug('');
        System.debug(text);
        System.debug(rule);
    }

    /**
     * Renders a value, keeping "returned as null" and "not returned" apart.
     *
     * Pass {@link ABSENT} for a field the API did not send.
     */
    public static String render(Object value) {
        if (value == ABSENT) {
            return ABSENT;
        }

        if (value == null) {
            return '<null>';
        }

        if (value instanceof List<Object>) {
            List<Object> items = (List<Object>) value;

            return items.isEmpty() ? '<empty list>' : items.size() + ' entries';
        }

        if (value instanceof Map<String, Object>) {
            return ((Map<String, Object>) value).size() + ' fields';
        }

        if (value instanceof List<String>) {
            List<String> items = (List<String>) value;

            return items.isEmpty() ? '<empty list>' : '[' + String.join(items, ', ') + ']';
        }

        return String.valueOf(value);
    }

    /** Prints a labelled field. */
    public static void field(String label, Object value) {
        field(label, value, 32);
    }

    /** Prints a labelled field with an explicit label column width. */
    public static void field(String label, Object value, Integer width) {
        String padded = label;

        while (padded.length() < width) {
            padded += ' ';
        }

        System.debug('  ' + padded + ' ' + render(value));
    }

    /** Prints a bulleted line. */
    public static void bullet(String text) {
        System.debug('  - ' + text);
    }

    /** Prints a closing note. Used for policy statements and caveats. */
    public static void note(String text) {
        System.debug('');

        for (String line : text.split('\n')) {
            System.debug(line);
        }
    }

    /**
     * Reads a field as {@link ABSENT} when the API did not return it, and as
     * the value it sent otherwise — null included.
     */
    public static Object present(DataObject data, String name) {
        return data.has(name) ? data.get(name) : (Object) ABSENT;
    }
}
