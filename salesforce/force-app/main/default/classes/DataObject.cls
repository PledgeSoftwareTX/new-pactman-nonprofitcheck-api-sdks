/**
 * An immutable view over a decoded JSON object.
 *
 * Field names mirror the wire format exactly, so what you read in the Pactman
 * API reference is what you access in code — there is no rename table to keep
 * in sync. That is why the accessors below are `snake_case` rather than Apex's
 * usual camelCase: the Node SDK reads `nonprofit.organization_name`, and so
 * does this one.
 *
 * Fields the API adds in a future version stay readable through {@link get}
 * without a deserialization failure or a package upgrade. That matters more
 * here than in the other SDKs: `JSON.deserialize` into a typed Apex class
 * rejects attributes the class does not declare, and a managed package cannot
 * be hot-patched when the API grows a field.
 *
 * **`has()` answers "did the API return this field?"** It is true for a field
 * returned as `null`. That distinction is load-bearing for this API: "no data
 * for this source" and "this source says null" route differently, and
 * collapsing them loses a finding. Use {@link get} to read a value,
 * {@link has} to ask whether the API sent the field at all.
 */
global abstract class DataObject {
    protected final Map<String, Object> fields;

    protected DataObject(Map<String, Object> fields) {
        this.fields = fields == null ? new Map<String, Object>() : fields;
    }

    /** True when the API returned this field, including when it returned it as `null`. */
    global Boolean has(String field) {
        return fields.containsKey(field);
    }

    /**
     * The field's raw value, or `null` when the API did not return the field.
     *
     * Use {@link has} to tell "returned as null" from "not returned".
     */
    global Object get(String field) {
        return fields.get(field);
    }

    /** The field as text, or `null`. A non-string value is rendered with `String.valueOf`. */
    global String getString(String field) {
        Object value = fields.get(field);

        if (value == null) {
            return null;
        }

        return value instanceof String ? (String) value : String.valueOf(value);
    }

    /** The field as a Boolean, or `null` when absent, null, or not a Boolean. */
    global Boolean getBoolean(String field) {
        Object value = fields.get(field);
        return value instanceof Boolean ? (Boolean) value : null;
    }

    /**
     * The field as an Integer, or `null`.
     *
     * `JSON.deserializeUntyped` types a JSON number as Integer, Long, Double or
     * Decimal depending on how it was written, so every numeric shape is
     * accepted rather than cast blindly.
     */
    global Integer getInteger(String field) {
        return asInteger(fields.get(field));
    }

    /** The field as a Decimal, or `null`. Accepts any numeric shape. */
    global Decimal getDecimal(String field) {
        return asDecimal(fields.get(field));
    }

    /**
     * Coerces a decoded JSON number to an Integer, or `null`.
     *
     * Package-internal, for reading the envelope's own numeric fields.
     */
    public static Integer asInteger(Object value) {
        Decimal number = asDecimal(value);
        return number == null ? null : number.intValue();
    }

    /** Coerces a decoded JSON number to a Decimal, or `null`. Package-internal. */
    public static Decimal asDecimal(Object value) {
        if (value instanceof Decimal) {
            return (Decimal) value;
        }

        if (value instanceof Double) {
            return Decimal.valueOf((Double) value);
        }

        if (value instanceof Long) {
            return Decimal.valueOf((Long) value);
        }

        if (value instanceof Integer) {
            return Decimal.valueOf((Integer) value);
        }

        return null;
    }

    /** The field as a list, or `null` when absent, null, or not an array. */
    global List<Object> getList(String field) {
        Object value = fields.get(field);
        return value instanceof List<Object> ? (List<Object>) value : null;
    }

    /** The field as a nested object, or `null` when absent, null, or not an object. */
    global Map<String, Object> getMap(String field) {
        Object value = fields.get(field);
        return value instanceof Map<String, Object> ? (Map<String, Object>) value : null;
    }

    /** Every field name the API returned, including those this SDK does not declare. */
    global Set<String> keys() {
        return fields.keySet();
    }

    /** The unmodified fields, exactly as they were decoded. A shallow copy. */
    global Map<String, Object> toMap() {
        return fields.clone();
    }

    /** The unmodified fields, re-serialized. */
    global String toJson() {
        return JSON.serialize(fields);
    }

    global override String toString() {
        return toJson();
    }
}
