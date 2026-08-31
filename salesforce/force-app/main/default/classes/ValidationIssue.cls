/** One item that failed local validation. */
global class ValidationIssue {
    /** Human-readable reason the value was rejected. */
    global String message { get; private set; }

    /** Position in the input collection, for bulk calls. `null` for a single value. */
    global Integer index { get; private set; }

    /** The offending value, exactly as the caller supplied it. */
    global String value { get; private set; }

    global ValidationIssue(String message, Integer index, String value) {
        this.message = message;
        this.index = index;
        this.value = value;
    }

    global Map<String, Object> toMap() {
        return new Map<String, Object>{
            'message' => message,
            'index' => index,
            'value' => value
        };
    }
}
