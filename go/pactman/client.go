package pactman

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"net/url"
	"strings"
	"time"
)

// Client is the entry point for the SDK.
//
// Build one per process and share it: a Client is safe for concurrent use,
// reuses connections, and carries the throttle state when a request-per-second
// ceiling is set.
//
// Server-side use only. The API key is a private credential. No diagnostic
// surface of a Client — fmt verbs, json.Marshal, slog — contains it.
type Client struct {
	// Nonprofits holds the nonprofit lookups.
	Nonprofits *NonprofitsResource

	transport *transport
}

// NewClient builds a client. The API key is required; load it from the
// environment or a secret manager, never from source:
//
//	client, err := pactman.NewClient(os.Getenv("PACTMAN_API_KEY"))
//
// A blank key, or an unusable option, returns a *ConfigurationError before any
// request is made.
func NewClient(apiKey string, opts ...ClientOption) (*Client, error) {
	return newClient(apiKey, defaultHooks(), opts)
}

func newClient(apiKey string, h hooks, opts []ClientOption) (*Client, error) {
	key := strings.TrimSpace(apiKey)
	if key == "" {
		return nil, &ConfigurationError{msg: "the Pactman API key is empty; pass it to NewClient, " +
			`for example from os.Getenv("PACTMAN_API_KEY"), and check that the variable is set`}
	}

	baseURL, err := BaseURLForEnvironment(DefaultEnvironment)
	if err != nil {
		return nil, err
	}

	config := clientConfig{
		baseURL:     baseURL,
		environment: DefaultEnvironment,
		timeout:     DefaultTimeout,
		retry:       DefaultRetryPolicy(),
		headers:     http.Header{},
		httpClient:  &http.Client{},
	}

	for _, opt := range opts {
		if opt == nil {
			continue
		}

		if err := opt.applyClient(&config); err != nil {
			return nil, err
		}
	}

	t := &transport{apiKey: secret(key), config: config, hooks: h, userAgent: userAgent()}

	return &Client{Nonprofits: &NonprofitsResource{transport: t}, transport: t}, nil
}

// BaseURL returns the resolved base URL every request is sent to.
func (c *Client) BaseURL() string { return c.transport.config.baseURL }

// Environment returns the named environment in use, or "" when WithBaseURL
// gave an explicit host.
func (c *Client) Environment() Environment { return c.transport.config.environment }

// Timeout returns the per-attempt timeout.
func (c *Client) Timeout() time.Duration { return c.transport.config.timeout }

// RetryPolicy returns a copy of the client's retry policy — a starting point
// for a per-call WithRetryPolicy.
func (c *Client) RetryPolicy() RetryPolicy { return c.transport.config.retry.clone() }

// String identifies the client by its base URL.
func (c *Client) String() string { return "pactman.Client(" + c.BaseURL() + ")" }

// GoString keeps %#v free of the API key.
func (c *Client) GoString() string { return c.String() }

// Format keeps every fmt verb free of the API key.
func (c *Client) Format(f fmt.State, _ rune) { io.WriteString(f, c.String()) }

// LogValue keeps slog output free of the API key.
func (c *Client) LogValue() slog.Value {
	return slog.GroupValue(
		slog.String("baseUrl", c.BaseURL()),
		slog.String("environment", string(c.Environment())),
		slog.Duration("timeout", c.Timeout()),
		slog.String("apiKey", redacted),
	)
}

// MarshalJSON renders a redacted view of the configuration.
func (c *Client) MarshalJSON() ([]byte, error) {
	config := c.transport.config

	var environment, rate any
	if config.environment != "" {
		environment = config.environment
	}

	if config.maxRequestsPerSecond > 0 {
		rate = config.maxRequestsPerSecond
	}

	return json.Marshal(map[string]any{
		"baseUrl":     config.baseURL,
		"environment": environment,
		"timeoutMs":   config.timeout.Milliseconds(),
		"retry": map[string]any{
			"maxRetries":        config.retry.MaxRetries,
			"initialDelayMs":    config.retry.InitialDelay.Milliseconds(),
			"maxDelayMs":        config.retry.MaxDelay.Milliseconds(),
			"backoffFactor":     config.retry.BackoffFactor,
			"jitter":            config.retry.Jitter,
			"retryableStatuses": config.retry.RetryableStatuses,
			"respectRetryAfter": config.retry.RespectRetryAfter,
		},
		"maxRequestsPerSecond": rate,
		"userAgent":            c.transport.userAgent,
		"apiKey":               redacted,
	})
}

// NonprofitsResource holds the nonprofit lookups. Reach it through
// Client.Nonprofits.
type NonprofitsResource struct {
	transport *transport
}

// String identifies the resource without its credentials.
func (r *NonprofitsResource) String() string { return "pactman.NonprofitsResource" }

// Format keeps every fmt verb free of the API key.
func (r *NonprofitsResource) Format(f fmt.State, _ rune) { io.WriteString(f, r.String()) }

// Check looks up a single nonprofit by EIN.
//
// The EIN is normalized and validated locally first; a malformed EIN returns a
// *ValidationError without sending a request. When ctx ends, the in-flight
// attempt and every planned retry stop.
//
//	result, err := client.Nonprofits.Check(ctx, "41-1787097")
func (r *NonprofitsResource) Check(ctx context.Context, ein string, opts ...RequestOption) (*SingleCheckResult, error) {
	if ctx == nil {
		return nil, &ValidationError{msg: "Check was given a nil context; pass context.Background() or a request context"}
	}

	normalized, err := NormalizeEIN(ein)
	if err != nil {
		return nil, err
	}

	settings, err := r.transport.requestSettings(opts)
	if err != nil {
		return nil, err
	}

	path := strings.Replace(SingleCheckPath, "{ein}", url.PathEscape(normalized), 1)

	res, err := r.transport.send(ctx, http.MethodGet, path, nil, settings)
	if err != nil {
		return nil, err
	}

	envelope := readEnvelope(res.body)

	return &SingleCheckResult{
		Result:    resultFrom(res, envelope),
		Nonprofit: extractNonprofit(envelope),
	}, nil
}

// CheckBulk looks up to MaxBulkEINs nonprofits in one request.
//
// Every EIN is normalized and validated before anything is sent; if any one
// fails, the call returns a *ValidationError identifying each offending index,
// and no request is made. EINs are sent in the order supplied and duplicates
// are kept unless WithDedupe is passed — but the API matches by set
// membership, so the response is not ordered to match and a repeated EIN comes
// back once. Index Organizations by EIN rather than pairing positionally.
//
// EINs the API has no record for are not an error: they arrive on an HTTP 200
// in NotFoundEINs. Larger inputs are rejected rather than split; this SDK never
// turns one call into several billable requests.
func (r *NonprofitsResource) CheckBulk(ctx context.Context, eins []string, opts ...RequestOption) (*BulkCheckResult, error) {
	if ctx == nil {
		return nil, &ValidationError{msg: "CheckBulk was given a nil context; pass context.Background() or a request context"}
	}

	if len(eins) == 0 {
		return nil, &ValidationError{msg: "CheckBulk requires at least one EIN"}
	}

	normalized, err := NormalizeEINs(eins)
	if err != nil {
		return nil, err
	}

	settings, err := r.transport.requestSettings(opts)
	if err != nil {
		return nil, err
	}

	if settings.dedupe {
		normalized = dedupe(normalized)
	}

	if len(normalized) > MaxBulkEINs {
		return nil, &ValidationError{msg: fmt.Sprintf(
			"CheckBulk accepts at most %d EINs per request, received %d; "+
				"split the input into batches, this SDK does not chunk automatically",
			MaxBulkEINs, len(normalized))}
	}

	payload, err := json.Marshal(normalized)
	if err != nil {
		return nil, err
	}

	res, err := r.transport.send(ctx, http.MethodPost, BulkCheckPath, payload, settings)
	if err != nil {
		return nil, err
	}

	envelope := readEnvelope(res.body)
	result := resultFrom(res, envelope)

	return &BulkCheckResult{
		Result:        result,
		Organizations: extractOrganizations(envelope),
		NotFoundEINs:  extractNotFoundEINs(result.Errors),
	}, nil
}

func dedupe(eins []string) []string {
	seen := make(map[string]bool, len(eins))
	unique := make([]string, 0, len(eins))

	for _, ein := range eins {
		if !seen[ein] {
			seen[ein] = true
			unique = append(unique, ein)
		}
	}

	return unique
}

// readEnvelope reads a successful response body. A body that is not a JSON
// object is kept as the raw value, with no fields.
func readEnvelope(body []byte) Envelope {
	trimmed := bytes.TrimSpace(body)

	var envelope Envelope

	if fields, err := parseObject(trimmed); err == nil {
		envelope.Fields = fields
		decodeDeclared(&envelope, fields)

		return envelope
	}

	switch {
	case len(trimmed) == 0:
	case json.Valid(trimmed):
		envelope.Fields = Object{src: append(json.RawMessage(nil), trimmed...)}
	default:
		envelope.Fields = Object{src: mustMarshal(string(trimmed))}
	}

	return envelope
}

func resultFrom(res *response, envelope Envelope) Result {
	result := Result{
		CheckCount: envelope.NonprofitCheckCount,
		Errors:     envelope.Errors,
		RequestID:  res.requestID,
		Status:     res.status,
		Raw:        envelope,
	}

	if result.Errors == nil {
		result.Errors = []APIErrorDetail{}
	}

	if envelope.TimeTaken != nil {
		taken := time.Duration(*envelope.TimeTaken * float64(time.Millisecond))
		result.TimeTaken = &taken
	}

	return result
}

func extractNonprofit(envelope Envelope) *Nonprofit {
	data, ok := envelope.Fields.Get("data")
	if !ok {
		return nil
	}

	var list []json.RawMessage
	if json.Unmarshal(data, &list) == nil {
		if len(list) == 0 {
			return nil
		}

		data = list[0]
	}

	return nonprofitFrom(data)
}

// extractOrganizations reads the bulk records. The published schema returns
// data as an array; some deployments wrap it as {"organizations": [...]}, so
// both are accepted rather than silently yielding an empty list.
func extractOrganizations(envelope Envelope) []*Nonprofit {
	organizations := []*Nonprofit{}

	data, ok := envelope.Fields.Get("data")
	if !ok {
		return organizations
	}

	if wrapped, err := parseObject(data); err == nil {
		if data, ok = wrapped.Get("organizations"); !ok {
			return organizations
		}
	}

	var list []json.RawMessage
	if json.Unmarshal(data, &list) != nil {
		return organizations
	}

	for _, entry := range list {
		if nonprofit := nonprofitFrom(entry); nonprofit != nil {
			organizations = append(organizations, nonprofit)
		}
	}

	return organizations
}

func nonprofitFrom(raw json.RawMessage) *Nonprofit {
	fields, err := parseObject(raw)
	if err != nil {
		return nil
	}

	nonprofit := &Nonprofit{Fields: fields}
	decodeDeclared(nonprofit, fields)

	return nonprofit
}

func extractNotFoundEINs(details []APIErrorDetail) []string {
	found := []string{}

	for _, detail := range details {
		found = append(found, detail.EINs...)
	}

	return found
}

const redacted = "[redacted]"

// secret holds the API key. Every formatting path that can reach it prints a
// placeholder; reveal is the one way to read it, and only the Authorization
// header calls it.
type secret string

func (s secret) reveal() string             { return string(s) }
func (secret) String() string               { return redacted }
func (secret) GoString() string             { return `"` + redacted + `"` }
func (secret) Format(f fmt.State, _ rune)   { io.WriteString(f, redacted) }
func (secret) MarshalJSON() ([]byte, error) { return []byte(`"` + redacted + `"`), nil }
func (secret) LogValue() slog.Value         { return slog.StringValue(redacted) }
