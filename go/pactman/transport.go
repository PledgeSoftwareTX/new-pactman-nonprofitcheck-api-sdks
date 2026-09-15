package pactman

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"io"
	"math"
	"math/rand/v2"
	"net/http"
	"strconv"
	"strings"
	"sync"
	"time"
)

// hooks are the clock and random source, substituted by the tests.
type hooks struct {
	// sleep waits for d, or returns ctx's error if it ends first.
	sleep func(ctx context.Context, d time.Duration) error
	// random returns a value in [0, 1), for backoff jitter.
	random func() float64
	now    func() time.Time
}

func defaultHooks() hooks {
	return hooks{sleep: sleepContext, random: rand.Float64, now: time.Now}
}

// transport issues authenticated requests: headers, per-attempt timeouts,
// cancellation, retries with jittered backoff, Retry-After, and mapping
// responses onto the error taxonomy.
//
// The API key is written into the Authorization header at send time and is
// never stored on a request record, an error, or any diagnostic output.
type transport struct {
	apiKey    secret
	config    clientConfig
	hooks     hooks
	userAgent string

	// mu guards nextRequestAt: a client is shared across goroutines.
	mu            sync.Mutex
	nextRequestAt time.Time
}

// response is a successful HTTP response and the metadata a result needs.
type response struct {
	status    int
	requestID string
	body      []byte
	attempts  int
}

// requestSettings resolves a call's options over the client's settings.
func (t *transport) requestSettings(opts []RequestOption) (requestConfig, error) {
	settings := requestConfig{
		timeout: t.config.timeout,
		retry:   t.config.retry.clone(),
		headers: http.Header{},
	}

	for _, opt := range opts {
		if opt == nil {
			continue
		}

		if err := opt.applyRequest(&settings); err != nil {
			return requestConfig{}, err
		}
	}

	return settings, nil
}

func (t *transport) send(ctx context.Context, method, path string, payload []byte, settings requestConfig) (*response, error) {
	url := t.config.baseURL + path
	retry := settings.retry

	for attempt := 1; ; attempt++ {
		if err := ctx.Err(); err != nil {
			return nil, aborted(attempt-1, err)
		}

		if err := t.throttle(ctx); err != nil {
			return nil, aborted(attempt-1, err)
		}

		res, err := t.attempt(ctx, method, url, payload, settings, attempt)

		if err != nil {
			// A timeout or a transport failure is retried; the caller giving up is not.
			if attempt > retry.MaxRetries || ctx.Err() != nil {
				return nil, err
			}

			if err := t.waitBeforeRetry(ctx, attempt, retry, nil); err != nil {
				return nil, aborted(attempt, err)
			}

			continue
		}

		if res.StatusCode >= 200 && res.StatusCode < 300 {
			return &response{
				status:    res.StatusCode,
				requestID: readRequestID(res.Header),
				body:      res.body,
				attempts:  attempt,
			}, nil
		}

		retryAfter := readRetryAfter(res.Header.Get("Retry-After"), t.hooks.now())
		apiErr := buildAPIError(res.StatusCode, res.body, readRequestID(res.Header), retryAfter, attempt)

		if attempt > retry.MaxRetries || !retry.retries(res.StatusCode) {
			return nil, apiErr
		}

		if err := t.waitBeforeRetry(ctx, attempt, retry, retryAfter); err != nil {
			return nil, aborted(attempt, err)
		}
	}
}

// httpResult is a response whose body has been read in full.
type httpResult struct {
	*http.Response
	body []byte
}

// attempt makes one request. The per-attempt timeout covers reading the body
// as well as waiting for the headers.
func (t *transport) attempt(ctx context.Context, method, url string, payload []byte, settings requestConfig, attempt int) (*httpResult, error) {
	attemptCtx, cancel := context.WithTimeout(ctx, settings.timeout)
	defer cancel()

	var body io.Reader
	if payload != nil {
		body = bytes.NewReader(payload)
	}

	req, err := http.NewRequestWithContext(attemptCtx, method, url, body)
	if err != nil {
		return nil, &NetworkError{Attempts: attempt, msg: "the request could not be built", cause: err}
	}

	req.Header = t.headers(settings.headers, payload != nil)

	res, err := t.config.httpClient.Do(req)
	if err == nil {
		data, readErr := io.ReadAll(res.Body)
		res.Body.Close()

		if readErr == nil {
			return &httpResult{Response: res, body: data}, nil
		}

		err = readErr
	}

	// The caller's context is checked first: when its deadline is the earlier
	// one, both contexts report it, and it is the caller who gave up.
	if ctx.Err() != nil {
		return nil, aborted(attempt, ctx.Err())
	}

	if errors.Is(attemptCtx.Err(), context.DeadlineExceeded) {
		return nil, &TimeoutError{Timeout: settings.timeout, Attempts: attempt}
	}

	return nil, &NetworkError{Attempts: attempt, msg: "the request to the Pactman API failed", cause: err}
}

// Header names this SDK owns. A caller's value for one is dropped rather than
// sent beside the real one.
var reservedHeaders = []string{"Authorization", "Accept", "User-Agent", "Content-Type"}

func (t *transport) headers(perRequest http.Header, hasBody bool) http.Header {
	headers := t.config.headers.Clone()

	for name, values := range perRequest {
		headers[name] = append([]string(nil), values...)
	}

	for _, name := range reservedHeaders {
		headers.Del(name)
	}

	headers.Set("Accept", "application/json")
	headers.Set("User-Agent", t.userAgent)
	headers.Set("Authorization", "Bearer "+t.apiKey.reveal())

	if hasBody {
		headers.Set("Content-Type", "application/json")
	}

	return headers
}

// throttle spaces requests when a request-per-second ceiling is configured.
func (t *transport) throttle(ctx context.Context) error {
	limit := t.config.maxRequestsPerSecond
	if limit == 0 {
		return nil
	}

	interval := time.Duration(float64(time.Second) / limit)

	t.mu.Lock()
	now := t.hooks.now()
	scheduled := now

	if t.nextRequestAt.After(now) {
		scheduled = t.nextRequestAt
	}

	t.nextRequestAt = scheduled.Add(interval)
	t.mu.Unlock()

	if wait := scheduled.Sub(now); wait > 0 {
		return t.hooks.sleep(ctx, wait)
	}

	return nil
}

func (t *transport) waitBeforeRetry(ctx context.Context, attempt int, retry RetryPolicy, retryAfter *time.Duration) error {
	return t.hooks.sleep(ctx, computeRetryDelay(attempt, retry, retryAfter, t.hooks.random))
}

// computeRetryDelay is the delay before the next attempt.
//
// A usable Retry-After wins outright. Otherwise the delay grows exponentially
// from InitialDelay, is capped at MaxDelay, and — with jitter on — is
// randomized across the whole range so concurrent clients spread out. Delays
// are whole milliseconds.
func computeRetryDelay(attempt int, retry RetryPolicy, retryAfter *time.Duration, random func() float64) time.Duration {
	if retry.RespectRetryAfter && retryAfter != nil && *retryAfter >= 0 {
		return roundToMillisecond(float64(*retryAfter))
	}

	exponential := float64(retry.InitialDelay) * math.Pow(retry.BackoffFactor, float64(attempt-1))
	capped := math.Min(exponential, float64(retry.MaxDelay))

	if retry.Jitter {
		capped *= random()
	}

	return roundToMillisecond(capped)
}

func roundToMillisecond(nanoseconds float64) time.Duration {
	return time.Duration(math.Round(nanoseconds/float64(time.Millisecond))) * time.Millisecond
}

// readRetryAfter reads Retry-After as a delay in seconds or an HTTP date, or
// returns nil when there is no usable value.
func readRetryAfter(header string, now time.Time) *time.Duration {
	raw := strings.TrimSpace(header)
	if raw == "" {
		return nil
	}

	if seconds, err := strconv.ParseFloat(raw, 64); err == nil {
		if math.IsNaN(seconds) || math.IsInf(seconds, 0) || seconds < 0 {
			return nil
		}

		delay := time.Duration(math.MaxInt64)
		if seconds < float64(math.MaxInt64)/float64(time.Second) {
			delay = time.Duration(seconds * float64(time.Second))
		}

		return &delay
	}

	when, ok := parseHTTPDate(raw)
	if !ok {
		return nil
	}

	delay := max(when.Sub(now), 0)

	return &delay
}

// parseHTTPDate reads the IMF-fixdate form HTTP specifies, its two obsolete
// forms, and RFC 1123 with a zone other than GMT, which servers send too.
func parseHTTPDate(raw string) (time.Time, bool) {
	if when, err := http.ParseTime(raw); err == nil {
		return when, true
	}

	for _, layout := range []string{time.RFC1123, time.RFC1123Z} {
		if when, err := time.Parse(layout, raw); err == nil {
			return when, true
		}
	}

	return time.Time{}, false
}

func readRequestID(headers http.Header) string {
	for _, name := range []string{"X-Request-Id", "X-Correlation-Id", "Request-Id"} {
		if value := headers.Get(name); value != "" {
			return value
		}
	}

	return ""
}

// buildAPIError maps an error response onto an *APIError, keeping its
// metadata even when the body is not the JSON envelope.
func buildAPIError(status int, body []byte, requestID string, retryAfter *time.Duration, attempts int) *APIError {
	apiErr := &APIError{
		Status:     status,
		RequestID:  requestID,
		RetryAfter: retryAfter,
		Body:       body,
		Attempts:   attempts,
		APIErrors:  []APIErrorDetail{},
	}

	trimmed := bytes.TrimSpace(body)

	if fields, err := parseObject(trimmed); err == nil {
		var envelope Envelope

		envelope.Fields = fields
		decodeDeclared(&envelope, fields)

		if envelope.Errors != nil {
			apiErr.APIErrors = envelope.Errors
		}

		apiErr.APICode = envelope.Code

		var reasons []string

		for _, detail := range apiErr.APIErrors {
			if strings.TrimSpace(detail.Reason) != "" {
				reasons = append(reasons, detail.Reason)
			}
		}

		switch {
		case len(reasons) > 0:
			apiErr.APIMessage = strings.Join(reasons, "; ")
		case envelope.Message != nil:
			apiErr.APIMessage = *envelope.Message
		}
	} else if text, ok := bodyText(trimmed); ok {
		apiErr.APIMessage = truncateRunes(text, 500)
	}

	return errorFromStatus(apiErr)
}

// bodyText is a body that is text rather than a JSON object: a JSON string's
// value, or the body itself when it is not JSON at all.
func bodyText(trimmed []byte) (string, bool) {
	if len(trimmed) == 0 {
		return "", false
	}

	if !json.Valid(trimmed) {
		return string(trimmed), true
	}

	var text string
	if json.Unmarshal(trimmed, &text) == nil && strings.TrimSpace(text) != "" {
		return strings.TrimSpace(text), true
	}

	return "", false
}

func truncateRunes(text string, limit int) string {
	runes := []rune(text)
	if len(runes) <= limit {
		return text
	}

	return string(runes[:limit])
}

func aborted(attempts int, cause error) *NetworkError {
	return &NetworkError{Attempts: attempts, msg: "the request was aborted by the caller", cause: cause}
}

func sleepContext(ctx context.Context, d time.Duration) error {
	if d <= 0 {
		return ctx.Err()
	}

	timer := time.NewTimer(d)
	defer timer.Stop()

	select {
	case <-timer.C:
		return nil
	case <-ctx.Done():
		return ctx.Err()
	}
}
