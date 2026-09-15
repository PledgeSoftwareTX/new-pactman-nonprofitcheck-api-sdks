package pactman

import (
	"encoding/json"
	"fmt"
	"strings"
	"time"
)

// ErrorCategory is a stable, machine-comparable error category. Branch on it,
// on the error's type, or on the Err* sentinels with errors.Is — never on
// message text.
type ErrorCategory string

// Error categories. Every error this SDK returns carries exactly one.
const (
	// CategoryConfiguration: the client was given unusable options.
	CategoryConfiguration ErrorCategory = "configuration"
	// CategoryValidation: input failed local validation; no request was sent.
	CategoryValidation ErrorCategory = "validation"
	// CategoryAuthentication: HTTP 401. The key is missing, malformed, revoked or unrecognized.
	CategoryAuthentication ErrorCategory = "authentication"
	// CategoryAuthorization: HTTP 403. The key is valid but lacks access.
	CategoryAuthorization ErrorCategory = "authorization"
	// CategoryBadRequest: HTTP 400. The API rejected the request.
	CategoryBadRequest ErrorCategory = "bad_request"
	// CategoryNotFound: HTTP 404. No matching record.
	CategoryNotFound ErrorCategory = "not_found"
	// CategoryRateLimit: HTTP 429. Rate limit exceeded.
	CategoryRateLimit ErrorCategory = "rate_limit"
	// CategoryServer: HTTP 5xx.
	CategoryServer ErrorCategory = "server"
	// CategoryTimeout: an attempt exceeded the configured timeout.
	CategoryTimeout ErrorCategory = "timeout"
	// CategoryNetwork: no HTTP response was produced, or the caller cancelled.
	CategoryNetwork ErrorCategory = "network"
	// CategoryAPI: an API error that fits no more specific category.
	CategoryAPI ErrorCategory = "api"
)

// ErrorOrigin says whether an error was raised locally or derived from an API
// response.
type ErrorOrigin string

// Error origins.
const (
	OriginLocal ErrorOrigin = "local"
	OriginAPI   ErrorOrigin = "api"
)

// Error is implemented by every error this SDK returns. Use errors.As to reach
// it through any wrapping:
//
//	var perr pactman.Error
//	if errors.As(err, &perr) { log.Println(perr.Category(), perr.Origin()) }
//
// No Error carries the API key in its message, its fields, or its JSON form.
type Error interface {
	error
	Category() ErrorCategory
	Origin() ErrorOrigin
}

// Sentinels for errors.Is. Each matches every SDK error of its category:
//
//	if errors.Is(err, pactman.ErrNotFound) { ... }
//
// Reach the details with errors.As and the concrete type — *APIError for
// every HTTP category, *ValidationError, *TimeoutError, *NetworkError, or
// *ConfigurationError.
var (
	ErrConfiguration  error = &sentinel{CategoryConfiguration}
	ErrValidation     error = &sentinel{CategoryValidation}
	ErrAuthentication error = &sentinel{CategoryAuthentication}
	ErrAuthorization  error = &sentinel{CategoryAuthorization}
	ErrBadRequest     error = &sentinel{CategoryBadRequest}
	ErrNotFound       error = &sentinel{CategoryNotFound}
	ErrRateLimit      error = &sentinel{CategoryRateLimit}
	ErrServer         error = &sentinel{CategoryServer}
	ErrTimeout        error = &sentinel{CategoryTimeout}
	ErrNetwork        error = &sentinel{CategoryNetwork}
)

type sentinel struct{ category ErrorCategory }

func (s *sentinel) Error() string { return "pactman: " + string(s.category) }

func matches(target error, category ErrorCategory) bool {
	s, ok := target.(*sentinel)

	return ok && s.category == category
}

// ConfigurationError reports unusable client options: a blank API key, a
// malformed base URL, a nonsensical timeout.
type ConfigurationError struct{ msg string }

func (e *ConfigurationError) Error() string           { return "pactman: " + e.msg }
func (e *ConfigurationError) Category() ErrorCategory { return CategoryConfiguration }
func (e *ConfigurationError) Origin() ErrorOrigin     { return OriginLocal }
func (e *ConfigurationError) Is(target error) bool    { return matches(target, CategoryConfiguration) }

// MarshalJSON renders a sanitized form, safe to log.
func (e *ConfigurationError) MarshalJSON() ([]byte, error) {
	return marshalBase(e, nil)
}

// ValidationIssue is one item that failed local validation.
type ValidationIssue struct {
	// Message says why the value was rejected.
	Message string `json:"message"`
	// Index is the item's position in the input list, or -1 when the value was
	// not part of a list.
	Index int `json:"index"`
	// Value is the offending value, as supplied.
	Value string `json:"value"`
}

// ValidationError reports input that failed local validation. No HTTP request
// was sent. Its origin is OriginLocal, which is what separates it from an
// API-side 400.
type ValidationError struct {
	msg string
	// Issues lists every rejected item. A bulk call reports all of them at once.
	Issues []ValidationIssue
}

func (e *ValidationError) Error() string           { return "pactman: " + e.msg }
func (e *ValidationError) Category() ErrorCategory { return CategoryValidation }
func (e *ValidationError) Origin() ErrorOrigin     { return OriginLocal }
func (e *ValidationError) Is(target error) bool    { return matches(target, CategoryValidation) }

// MarshalJSON renders a sanitized form, safe to log.
func (e *ValidationError) MarshalJSON() ([]byte, error) {
	issues := e.Issues
	if issues == nil {
		issues = []ValidationIssue{}
	}

	return marshalBase(e, map[string]any{"issues": issues})
}

// APIError is an error response from the Pactman API. Every HTTP failure is an
// *APIError; Category says which kind:
//
//	400 CategoryBadRequest       401 CategoryAuthentication
//	403 CategoryAuthorization    404 CategoryNotFound
//	429 CategoryRateLimit        5xx CategoryServer
//	anything else                CategoryAPI
//
// Response metadata is kept even when the body could not be decoded.
type APIError struct {
	// Status is the HTTP status code.
	Status int
	// APIMessage is the envelope's reasons joined, or its message, or the start
	// of a non-JSON body. Empty when the response carried none.
	APIMessage string
	// APICode is the envelope's code, when present.
	APICode *int
	// APIErrors is the envelope's errors, normalized to a list.
	APIErrors []APIErrorDetail
	// RequestID is the correlation identifier from the response headers.
	RequestID string
	// RetryAfter is the server's Retry-After, when it sent a usable value.
	RetryAfter *time.Duration
	// Body is the response body exactly as received. An undecodable body is
	// still evidence.
	Body []byte
	// Attempts is how many attempts were made before this error surfaced.
	Attempts int

	category ErrorCategory
	msg      string
}

func (e *APIError) Error() string {
	return fmt.Sprintf("pactman: %s (HTTP %d)", e.msg, e.Status)
}

func (e *APIError) Category() ErrorCategory { return e.category }
func (e *APIError) Origin() ErrorOrigin     { return OriginAPI }
func (e *APIError) Is(target error) bool    { return matches(target, e.category) }

// MarshalJSON renders a sanitized form, safe to log. Body is left out.
func (e *APIError) MarshalJSON() ([]byte, error) {
	var retryAfter any
	if e.RetryAfter != nil {
		retryAfter = e.RetryAfter.Seconds()
	}

	details := e.APIErrors
	if details == nil {
		details = []APIErrorDetail{}
	}

	return marshalBase(e, map[string]any{
		"status":            e.Status,
		"apiMessage":        nullIfEmpty(e.APIMessage),
		"apiCode":           e.APICode,
		"apiErrors":         details,
		"requestId":         nullIfEmpty(e.RequestID),
		"retryAfterSeconds": retryAfter,
		"attempts":          e.Attempts,
	})
}

// TimeoutError reports an attempt that exceeded the configured per-attempt
// timeout.
//
// The caller's own context ending is a *NetworkError, not this, and a
// TimeoutError deliberately does not match context.DeadlineExceeded: the two
// mean different things — raise the budget or shed load, versus the caller
// went away — and conflating them hides which side gave up.
type TimeoutError struct {
	// Timeout is the per-attempt timeout that expired.
	Timeout time.Duration
	// Attempts is how many attempts were made.
	Attempts int
}

func (e *TimeoutError) Error() string {
	return fmt.Sprintf("pactman: the request timed out after %s", e.Timeout)
}

func (e *TimeoutError) Category() ErrorCategory { return CategoryTimeout }
func (e *TimeoutError) Origin() ErrorOrigin     { return OriginLocal }
func (e *TimeoutError) Is(target error) bool    { return matches(target, CategoryTimeout) }

// MarshalJSON renders a sanitized form, safe to log.
func (e *TimeoutError) MarshalJSON() ([]byte, error) {
	return marshalBase(e, map[string]any{
		"timeoutMs": e.Timeout.Milliseconds(),
		"attempts":  e.Attempts,
	})
}

// NetworkError reports a request that produced no HTTP response, or one the
// caller cancelled. When the caller's context ended, Unwrap returns its error,
// so errors.Is(err, context.Canceled) and context.DeadlineExceeded work.
type NetworkError struct {
	// Attempts is how many attempts were made; 0 when the context had already
	// ended before the first one.
	Attempts int

	msg   string
	cause error
}

func (e *NetworkError) Error() string {
	if e.cause == nil {
		return "pactman: " + e.msg
	}

	return "pactman: " + e.msg + ": " + e.cause.Error()
}

func (e *NetworkError) Category() ErrorCategory { return CategoryNetwork }
func (e *NetworkError) Origin() ErrorOrigin     { return OriginLocal }
func (e *NetworkError) Is(target error) bool    { return matches(target, CategoryNetwork) }
func (e *NetworkError) Unwrap() error           { return e.cause }

// MarshalJSON renders a sanitized form, safe to log.
func (e *NetworkError) MarshalJSON() ([]byte, error) {
	return marshalBase(e, map[string]any{"attempts": e.Attempts})
}

func marshalBase(e Error, extra map[string]any) ([]byte, error) {
	fields := map[string]any{
		"name":     strings.TrimPrefix(fmt.Sprintf("%T", e), "*pactman."),
		"message":  e.Error(),
		"category": e.Category(),
		"origin":   e.Origin(),
	}

	for key, value := range extra {
		fields[key] = value
	}

	return json.Marshal(fields)
}

func nullIfEmpty(value string) any {
	if value == "" {
		return nil
	}

	return value
}

// errorFromStatus builds the *APIError for an HTTP status.
func errorFromStatus(e *APIError) *APIError {
	e.category = categoryForStatus(e.Status)
	e.msg = strings.TrimSpace(e.APIMessage)

	if e.msg == "" {
		e.msg = defaultMessageForStatus(e.Status)
	}

	return e
}

func categoryForStatus(status int) ErrorCategory {
	switch {
	case status == 400:
		return CategoryBadRequest
	case status == 401:
		return CategoryAuthentication
	case status == 403:
		return CategoryAuthorization
	case status == 404:
		return CategoryNotFound
	case status == 429:
		return CategoryRateLimit
	case status >= 500:
		return CategoryServer
	default:
		return CategoryAPI
	}
}

func defaultMessageForStatus(status int) string {
	switch {
	case status == 400:
		return "the Pactman API rejected the request"
	case status == 401:
		return "the Pactman API key was rejected"
	case status == 403:
		return "this Pactman API key is not permitted to access that resource"
	case status == 404:
		return "no matching record was found"
	case status == 429:
		return "the Pactman API rate limit was exceeded"
	case status >= 500:
		return "the Pactman API returned a server error"
	default:
		return "the Pactman API returned an unexpected response"
	}
}
