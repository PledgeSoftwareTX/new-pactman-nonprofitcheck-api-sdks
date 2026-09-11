package org.pactman.nonprofitcheckplus.examples.support;

import java.util.Collection;
import java.util.Map;

/**
 * Console formatting for the examples.
 *
 * <p>The important rule here is {@link #render(Object)}: a field the API
 * returned as {@code null} and a field the API did not return at all print
 * differently. Collapsing them into {@code ""} or {@code "-"} is how a missing
 * value quietly becomes a match.
 */
public final class Output {

    /** What {@link #render(Object)} prints for a field the API did not return. */
    public static final Object ABSENT = new Object() {
        @Override
        public String toString() {
            return "<not returned>";
        }
    };

    private Output() {
    }

    /**
     * Prints a section heading.
     *
     * @param text the heading.
     */
    public static void heading(String text) {
        System.out.println();
        System.out.println(text);

        StringBuilder rule = new StringBuilder();

        for (int i = 0; i < text.length(); i++) {
            rule.append('─');
        }

        System.out.println(rule);
    }

    /**
     * Renders a value, keeping "returned as null" and "not returned" apart.
     *
     * @param value the value, or {@link #ABSENT} when the API sent no such field.
     * @return the text to print.
     */
    public static String render(Object value) {
        if (value == ABSENT) {
            return "<not returned>";
        }

        if (value == null) {
            return "<null>";
        }

        if (value instanceof Collection) {
            Collection<?> items = (Collection<?>) value;

            return items.isEmpty() ? "<empty list>" : items.size() + " entries";
        }

        if (value instanceof Map) {
            return ((Map<?, ?>) value).size() + " fields";
        }

        return String.valueOf(value);
    }

    /**
     * Prints a labelled field.
     *
     * @param label the label.
     * @param value the value.
     */
    public static void field(String label, Object value) {
        field(label, value, 32);
    }

    /**
     * Prints a labelled field with an explicit label width.
     *
     * @param label the label.
     * @param value the value.
     * @param width how wide the label column is.
     */
    public static void field(String label, Object value, int width) {
        StringBuilder padded = new StringBuilder(label);

        while (padded.length() < width) {
            padded.append(' ');
        }

        System.out.println("  " + padded + " " + render(value));
    }

    /**
     * Prints a bulleted line.
     *
     * @param text the line.
     */
    public static void bullet(String text) {
        System.out.println("  • " + text);
    }

    /**
     * Prints a short note. Used for policy statements and caveats.
     *
     * @param text the note.
     */
    public static void note(String text) {
        System.out.println();
        System.out.println(text);
    }

    /**
     * Reads a field as {@link #ABSENT} when the API did not return it.
     *
     * @param object the response object.
     * @param field  the wire field name.
     * @return the value, {@code null}, or {@link #ABSENT}.
     */
    public static Object present(
            org.pactman.nonprofitcheckplus.models.DataObject object, String field) {
        return object.has(field) ? object.get(field) : ABSENT;
    }
}
