package org.pactman.nonprofitcheckplus.models;

import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.Map;

/**
 * One entry from the envelope's {@code errors} array.
 *
 * <p>These arrive on successful responses too: a bulk request where some EINs
 * were not found returns HTTP 200 with entries here.
 */
public final class ApiErrorDetail extends DataObject {

    /**
     * Initializes the detail from a decoded JSON object.
     *
     * @param fields the detail as the API sent it.
     */
    public ApiErrorDetail(Map<String, Object> fields) {
        super(fields);
    }

    /**
     * Reads a decoded envelope {@code errors} value as a list of details.
     *
     * <p>The field is an array on most responses, but a bare string on some, and
     * absent on a clean one. All three are accepted rather than silently
     * yielding an empty list and losing the reason the API gave.
     *
     * @param value the decoded field value.
     * @return the details. Empty when the API reported none.
     */
    public static List<ApiErrorDetail> listFrom(Object value) {
        if (value == null) {
            return Collections.emptyList();
        }

        if (value instanceof List) {
            List<?> raw = (List<?>) value;
            List<ApiErrorDetail> details = new ArrayList<>(raw.size());

            for (Object entry : raw) {
                if (entry instanceof Map) {
                    details.add(new ApiErrorDetail(asFields(entry)));
                }
            }

            return Collections.unmodifiableList(details);
        }

        if (value instanceof String) {
            String reason = (String) value;

            if (reason.trim().isEmpty()) {
                return Collections.emptyList();
            }

            Map<String, Object> fields = new java.util.LinkedHashMap<>();
            fields.put("reason", reason);

            return Collections.singletonList(new ApiErrorDetail(fields));
        }

        if (value instanceof Map) {
            return Collections.singletonList(new ApiErrorDetail(asFields(value)));
        }

        return Collections.emptyList();
    }

    /**
     * The API resource the error came from.
     *
     * @return the resource, or {@code null} when the API returned none.
     */
    public String getResource() {
        return getString("resource");
    }

    /**
     * Human-readable explanation.
     *
     * @return the reason, or {@code null} when the API returned none.
     */
    public String getReason() {
        return getString("reason");
    }

    /**
     * Status code for this specific failure, which may differ from the HTTP status.
     *
     * @return the code, or {@code null} when the API returned none.
     */
    public Integer getCode() {
        return getInteger("code");
    }

    /**
     * The EINs this error applies to, for bulk requests.
     *
     * <p>The API sends these as an array on most responses and as a
     * comma-separated string on some; both are read here, so a caller never has
     * to branch on the shape. Read {@code get("eins")} for the unmodified value.
     *
     * @return the EINs. Empty when the error names none.
     */
    public List<String> getEins() {
        Object value = get("eins");

        if (value instanceof List) {
            List<String> eins = new ArrayList<>();

            for (Object entry : (List<?>) value) {
                if (entry instanceof String) {
                    eins.add((String) entry);
                }
            }

            return Collections.unmodifiableList(eins);
        }

        if (value instanceof String) {
            List<String> eins = new ArrayList<>();

            for (String part : ((String) value).split(",")) {
                String trimmed = part.trim();

                if (!trimmed.isEmpty()) {
                    eins.add(trimmed);
                }
            }

            return Collections.unmodifiableList(eins);
        }

        return Collections.emptyList();
    }
}
