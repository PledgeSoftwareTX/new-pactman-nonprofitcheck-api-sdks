/**
 * HTTP 429.
 *
 * `retryAfterSeconds` carries the server's `Retry-After` when it sent one.
 * Apex has no sleep primitive, so the SDK never waits it out in-transaction —
 * hand the value to {@link CheckQueueable} to retry asynchronously instead.
 */
global class RateLimitException extends ApiException {}
