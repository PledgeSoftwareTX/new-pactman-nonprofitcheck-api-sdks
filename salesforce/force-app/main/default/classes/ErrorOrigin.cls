/** Whether an error was raised locally or derived from an API response. */
global enum ErrorOrigin {
    /** The SDK raised it without sending, or the callout never completed. */
    LOCAL,
    /** Derived from an HTTP response the API returned. */
    API
}
