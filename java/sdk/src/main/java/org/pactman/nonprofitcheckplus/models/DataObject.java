package org.pactman.nonprofitcheckplus.models;

import java.util.Collections;
import java.util.Iterator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import org.pactman.nonprofitcheckplus.internal.Json;

/**
 * An immutable view over a decoded JSON object.
 *
 * <p>Wire field names are preserved exactly, so what you read in the Pactman API
 * reference is what {@link #has(String)} and {@link #get(String)} take — there
 * is no rename table to keep in sync. The typed accessors on the subclasses are
 * conveniences over the same store, not a separate deserialization: a field the
 * API adds in a future version stays readable through {@link #get(String)}
 * without a deserialization failure or an SDK upgrade.
 *
 * <p><b>{@link #has(String)} answers "did the API return this field?"</b> — it
 * reports {@code true} for a field returned as JSON {@code null}. That
 * distinction is load-bearing for this API: "no data for this source" and "this
 * source says null" route differently, and collapsing them loses a finding. Use
 * {@link #get(String)} and the typed accessors to read the value,
 * {@link #has(String)} to ask whether the API sent the field at all.
 */
public abstract class DataObject implements Iterable<Map.Entry<String, Object>> {

    private final Map<String, Object> fields;

    /**
     * Initializes the view over a set of wire fields.
     *
     * @param fields the fields exactly as they were decoded, in document order.
     *               {@code null} yields an empty view.
     */
    protected DataObject(Map<String, Object> fields) {
        this.fields = fields == null
                ? Collections.<String, Object>emptyMap()
                : Collections.unmodifiableMap(new LinkedHashMap<>(fields));
    }

    /**
     * How many fields the API returned.
     *
     * @return the field count.
     */
    public int size() {
        return fields.size();
    }

    /**
     * The field names the API returned, in the order it returned them.
     *
     * @return the wire field names.
     */
    public java.util.Set<String> fieldNames() {
        return fields.keySet();
    }

    /**
     * True when the API returned this field, including when it returned it as
     * JSON {@code null}.
     *
     * @param field the wire field name.
     * @return whether the field was present in the response.
     */
    public boolean has(String field) {
        return field != null && fields.containsKey(field);
    }

    /**
     * The field's value, or {@code null} when the API did not return it.
     *
     * @param field the wire field name.
     * @return a {@link String}, {@link Boolean}, {@link Number}, {@link List},
     *         {@link Map}, or {@code null}.
     */
    public Object get(String field) {
        return field == null ? null : fields.get(field);
    }

    /**
     * The field as a string, or {@code null} when it is absent or JSON null.
     *
     * <p>A non-string value is returned as its JSON text, so a field the API
     * changes from a string to a number stays readable rather than vanishing.
     *
     * @param field the wire field name.
     * @return the string value, or {@code null}.
     */
    public String getString(String field) {
        Object value = get(field);

        if (value == null) {
            return null;
        }

        if (value instanceof String) {
            return (String) value;
        }

        return value instanceof Map || value instanceof List
                ? Json.write(value)
                : String.valueOf(value);
    }

    /**
     * The field as a boolean, or {@code null} when it is absent, JSON null, or
     * not a boolean.
     *
     * @param field the wire field name.
     * @return the boolean value, or {@code null}.
     */
    public Boolean getBoolean(String field) {
        Object value = get(field);

        return value instanceof Boolean ? (Boolean) value : null;
    }

    /**
     * The field as an integer, or {@code null} when it is absent, JSON null, or
     * not a number.
     *
     * @param field the wire field name.
     * @return the integer value, truncated toward zero, or {@code null}.
     */
    public Integer getInteger(String field) {
        Object value = get(field);

        return value instanceof Number ? Integer.valueOf(((Number) value).intValue()) : null;
    }

    /**
     * The field as a number, or {@code null} when it is absent, JSON null, or
     * not a number.
     *
     * @param field the wire field name.
     * @return the numeric value, or {@code null}.
     */
    public Double getDouble(String field) {
        Object value = get(field);

        return value instanceof Number ? Double.valueOf(((Number) value).doubleValue()) : null;
    }

    /**
     * The field as a list, or {@code null} when it is absent, JSON null, or not
     * an array.
     *
     * @param field the wire field name.
     * @return the list, or {@code null}.
     */
    @SuppressWarnings("unchecked")
    public List<Object> getList(String field) {
        Object value = get(field);

        return value instanceof List
                ? Collections.unmodifiableList((List<Object>) value)
                : null;
    }

    /**
     * The field as a nested object, or {@code null} when it is absent, JSON
     * null, or not an object.
     *
     * @param field the wire field name.
     * @return the nested fields, or {@code null}.
     */
    @SuppressWarnings("unchecked")
    public Map<String, Object> getMap(String field) {
        Object value = get(field);

        return value instanceof Map
                ? Collections.unmodifiableMap((Map<String, Object>) value)
                : null;
    }

    /**
     * The unmodified fields, exactly as they were decoded.
     *
     * @return the wire fields, in the order the API returned them.
     */
    public Map<String, Object> toMap() {
        return fields;
    }

    /**
     * The fields re-serialized as a JSON object, in the order the API returned them.
     *
     * @return a JSON object literal.
     */
    public String toJson() {
        return Json.write(fields);
    }

    @Override
    public Iterator<Map.Entry<String, Object>> iterator() {
        return fields.entrySet().iterator();
    }

    @Override
    public String toString() {
        return toJson();
    }

    /**
     * Reads a decoded value as an object's fields.
     *
     * @param value a decoded JSON value.
     * @return the fields, or an empty map when the value is not an object.
     */
    @SuppressWarnings("unchecked")
    protected static Map<String, Object> asFields(Object value) {
        return value instanceof Map
                ? (Map<String, Object>) value
                : Collections.<String, Object>emptyMap();
    }
}
