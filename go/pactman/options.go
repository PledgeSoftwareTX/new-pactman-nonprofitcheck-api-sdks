package pactman

import (
	"fmt"
	"math"
	"net/http"
	"net/url"
	"strings"
	"time"
)

// DefaultTimeout is the per-attempt timeout used when none is configured. The
// timeout is always finite; there is no way to disable it.
const DefaultTimeout = 30 * time.Second

// HTTPDoer sends HTTP requests. *http.Client satisfies it; so does any wrapper
// that counts, logs or proxies requests.
type HTTPDoer interface {
	Do(*http.Request) (*http.Response, error)
}

// RetryPolicy controls automatic retries. Start from DefaultRetryPolicy, or
// from Client.RetryPolicy, and change what you need.
type RetryPolicy struct {
	// MaxRetries is the retries after the first attempt. 0 disables retrying.
	MaxRetries int
	// InitialDelay is the delay before the first retry. Later delays grow by
	// BackoffFactor and are randomized when Jitter is on.
	InitialDelay time.Duration
	// MaxDelay caps a single backoff delay. A server-supplied Retry-After is
	// honored even when it exceeds this.
	MaxDelay time.Duration
	// BackoffFactor multiplies each successive delay. It must be 1 or more.
	BackoffFactor float64
	// Jitter randomizes each delay across [0, computed] (full jitter), so that
	// clients failing together do not retry in lockstep.
	Jitter bool
	// RetryableStatuses are the HTTP statuses worth retrying. 400, 401, 403 and
	// 404 are never retried, whatever this contains.
	RetryableStatuses []int
	// RespectRetryAfter waits for the server's Retry-After before falling back
	// to backoff.
	RespectRetryAfter bool
}

// DefaultRetryPolicy returns the policy a client uses unless told otherwise:
// two retries (three attempts), exponential backoff from 500ms with full
// jitter, capped at 8s per delay, on 429, 500, 502, 503 and 504, honoring
// Retry-After.
func DefaultRetryPolicy() RetryPolicy {
	return RetryPolicy{
		MaxRetries:        2,
		InitialDelay:      500 * time.Millisecond,
		MaxDelay:          8 * time.Second,
		BackoffFactor:     2,
		Jitter:            true,
		RetryableStatuses: []int{429, 500, 502, 503, 504},
		RespectRetryAfter: true,
	}
}

func (p RetryPolicy) clone() RetryPolicy {
	p.RetryableStatuses = append([]int(nil), p.RetryableStatuses...)

	return p
}

// problem says what is wrong with the policy, or "" when nothing is.
func (p RetryPolicy) problem() string {
	switch {
	case p.MaxRetries < 0:
		return "the retry policy's MaxRetries must be 0 or more"
	case p.InitialDelay < 0:
		return "the retry policy's InitialDelay must be 0 or more"
	case p.MaxDelay < 0:
		return "the retry policy's MaxDelay must be 0 or more"
	case math.IsNaN(p.BackoffFactor) || math.IsInf(p.BackoffFactor, 0) || p.BackoffFactor < 1:
		return "the retry policy's BackoffFactor must be a finite number of 1 or more"
	}

	return ""
}

// Statuses that are never retried, regardless of RetryableStatuses.
var neverRetry = map[int]bool{400: true, 401: true, 403: true, 404: true}

func (p RetryPolicy) retries(status int) bool {
	if neverRetry[status] {
		return false
	}

	for _, retryable := range p.RetryableStatuses {
		if retryable == status {
			return true
		}
	}

	return false
}

// ClientOption configures a Client. Pass it to NewClient.
type ClientOption interface {
	applyClient(*clientConfig) error
}

// RequestOption overrides the client's settings for one call.
type RequestOption interface {
	applyRequest(*requestConfig) error
}

// Option is accepted both by NewClient and by each call, where it overrides
// the client's setting for that call only.
type Option interface {
	ClientOption
	RequestOption
}

type clientConfig struct {
	baseURL              string
	environment          Environment
	timeout              time.Duration
	retry                RetryPolicy
	maxRequestsPerSecond float64
	headers              http.Header
	httpClient           HTTPDoer
}

type requestConfig struct {
	timeout time.Duration
	retry   RetryPolicy
	headers http.Header
	dedupe  bool
}

// option is every option's concrete type. problem carries a value rejected
// at construction, reported when the option is applied: as a
// *ConfigurationError by NewClient, and as a *ValidationError by a call.
type option struct {
	problem string
	client  func(*clientConfig)
	request func(*requestConfig)
}

func (o option) applyClient(c *clientConfig) error {
	if o.problem != "" {
		return &ConfigurationError{msg: o.problem}
	}

	if o.client != nil {
		o.client(c)
	}

	return nil
}

func (o option) applyRequest(r *requestConfig) error {
	if o.problem != "" {
		return &ValidationError{msg: o.problem}
	}

	if o.request != nil {
		o.request(r)
	}

	return nil
}

// WithEnvironment selects a named Pactman environment. Production is the
// default and the only named environment.
func WithEnvironment(environment Environment) ClientOption {
	baseURL, err := BaseURLForEnvironment(environment)
	if err != nil {
		return option{problem: strings.TrimPrefix(err.Error(), "pactman: ")}
	}

	return option{client: func(c *clientConfig) {
		c.baseURL, c.environment = baseURL, environment
	}}
}

// WithBaseURL sends requests to an explicit host — a mock server, a proxy, or a
// host Pactman has given you directly — instead of a named environment. It
// must be an http or https URL.
func WithBaseURL(baseURL string) ClientOption {
	resolved, problem := resolveBaseURL(baseURL)
	if problem != "" {
		return option{problem: problem}
	}

	return option{client: func(c *clientConfig) {
		c.baseURL, c.environment = resolved, ""
	}}
}

func resolveBaseURL(raw string) (string, string) {
	trimmed := strings.TrimSpace(raw)
	if trimmed == "" {
		return "", "the base URL must be a non-empty URL"
	}

	parsed, err := url.Parse(trimmed)
	if err != nil || parsed.Scheme == "" || parsed.Host == "" {
		return "", fmt.Sprintf("the base URL %q is not a valid URL; expected something like https://entities.pactman.org", raw)
	}

	if parsed.Scheme != "http" && parsed.Scheme != "https" {
		return "", fmt.Sprintf("the base URL must use http or https, received %q", parsed.Scheme)
	}

	return parsed.Scheme + "://" + strings.ToLower(parsed.Host) + strings.TrimRight(parsed.Path, "/"), ""
}

// WithTimeout sets the per-attempt timeout. It must be greater than zero.
func WithTimeout(timeout time.Duration) Option {
	if timeout <= 0 {
		return option{problem: "the timeout must be greater than zero; there is no way to disable it"}
	}

	return option{
		client:  func(c *clientConfig) { c.timeout = timeout },
		request: func(r *requestConfig) { r.timeout = timeout },
	}
}

// WithRetryPolicy replaces the retry policy.
func WithRetryPolicy(policy RetryPolicy) Option {
	if problem := policy.problem(); problem != "" {
		return option{problem: problem}
	}

	return option{
		client:  func(c *clientConfig) { c.retry = policy.clone() },
		request: func(r *requestConfig) { r.retry = policy.clone() },
	}
}

// WithMaxRetries changes only the number of retries after the first attempt,
// keeping the rest of the policy. 0 disables retrying.
func WithMaxRetries(retries int) Option {
	if retries < 0 {
		return option{problem: "the retry policy's MaxRetries must be 0 or more"}
	}

	return option{
		client:  func(c *clientConfig) { c.retry.MaxRetries = retries },
		request: func(r *requestConfig) { r.retry.MaxRetries = retries },
	}
}

// WithoutRetries disables retrying: every call makes exactly one attempt.
func WithoutRetries() Option {
	return WithMaxRetries(0)
}

// WithMaxRequestsPerSecond sets a client-side ceiling on outbound requests.
// It is off by default. The server's limits are authoritative and may change;
// treat this as a courtesy throttle, not a guarantee.
func WithMaxRequestsPerSecond(limit float64) ClientOption {
	if math.IsNaN(limit) || math.IsInf(limit, 0) || limit <= 0 {
		return option{problem: "the request-per-second ceiling must be a finite number greater than zero"}
	}

	return option{client: func(c *clientConfig) { c.maxRequestsPerSecond = limit }}
}

// WithHeader adds a header: to every request when given to NewClient, or to one
// call. It cannot override Authorization, Accept, User-Agent or Content-Type.
func WithHeader(name, value string) Option {
	if !validHeaderName(name) {
		return option{problem: fmt.Sprintf("%q is not a valid HTTP header name", name)}
	}

	if strings.ContainsAny(value, "\r\n") {
		return option{problem: fmt.Sprintf("the value for header %q contains a line break", name)}
	}

	return option{
		client:  func(c *clientConfig) { c.headers.Add(name, value) },
		request: func(r *requestConfig) { r.headers.Add(name, value) },
	}
}

// WithHTTPClient sends requests through your own HTTP client. The default is
// an *http.Client over http.DefaultTransport. The per-attempt timeout is
// applied through the request context, so the client needs no timeout of its own.
func WithHTTPClient(client HTTPDoer) ClientOption {
	if client == nil {
		return option{problem: "the HTTP client must not be nil"}
	}

	return option{client: func(c *clientConfig) { c.httpClient = client }}
}

// WithDedupe removes duplicate EINs from a CheckBulk call before it is sent,
// keeping first-seen order. Duplicates are collapsed after normalization and
// before the batch limit is applied.
//
// Off by default: duplicates are sent exactly as supplied, because each one
// consumes quota and silently dropping them would misreport what was checked.
// On Check, which sends one EIN, it has nothing to do.
func WithDedupe() RequestOption {
	return option{request: func(r *requestConfig) { r.dedupe = true }}
}

func validHeaderName(name string) bool {
	if name == "" {
		return false
	}

	for _, r := range name {
		if r <= ' ' || r >= 0x7f || strings.ContainsRune(`()<>@,;:\"/[]?={}`, r) {
			return false
		}
	}

	return true
}
