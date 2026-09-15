package pactman

import (
	"context"
	"errors"
	"fmt"
	"net/http"
	"slices"
	"sync"
	"testing"
	"time"
)

func noJitter(maxRetries int, initial time.Duration) RetryPolicy {
	policy := DefaultRetryPolicy()
	policy.MaxRetries = maxRetries
	policy.InitialDelay = initial
	policy.Jitter = false

	return policy
}

func TestAutomaticRetries(t *testing.T) {
	ctx := context.Background()
	serverError := stub{status: 500, body: errorEnvelope(500, "Internal Server Error").encode()}
	success := stub{body: envelope(wireNonprofit()).encode()}

	t.Run("succeeds after a temporary failure", func(t *testing.T) {
		doer := serving(stub{status: 503, body: errorEnvelope(503, "Service Unavailable").encode()}, success)

		result, err := newTestClient(t, doer, nil).Nonprofits.Check(ctx, "411787097")
		if err != nil || str(result.Nonprofit.EIN) != "411787097" || doer.calls() != 2 {
			t.Fatalf("result %+v, err %v, requests %d", result, err, doer.calls())
		}
	})

	t.Run("never exceeds the configured maximum attempt count", func(t *testing.T) {
		doer := serving(serverError)

		_, err := newTestClient(t, doer, nil, WithRetryPolicy(noJitter(3, 500*time.Millisecond))).Nonprofits.Check(ctx, "411787097")

		var apiErr *APIError
		if !errors.As(err, &apiErr) || apiErr.Category() != CategoryServer || apiErr.Attempts != 4 || doer.calls() != 4 {
			t.Fatalf("err %v, requests %d", err, doer.calls())
		}
	})

	t.Run("makes a single attempt when retries are disabled", func(t *testing.T) {
		doer := serving(serverError)
		_, _ = newTestClient(t, doer, nil, WithoutRetries()).Nonprofits.Check(ctx, "411787097")

		if doer.calls() != 1 {
			t.Errorf("requests = %d", doer.calls())
		}
	})

	t.Run("retries temporary network failures", func(t *testing.T) {
		doer := serving(stub{err: errors.New("connection refused")}, success)

		if _, err := newTestClient(t, doer, nil).Nonprofits.Check(ctx, "411787097"); err != nil || doer.calls() != 2 {
			t.Fatalf("err %v, requests %d", err, doer.calls())
		}
	})

	for _, status := range []int{400, 401, 403, 404} {
		t.Run(fmt.Sprintf("never retries a %d, even when listed as retryable", status), func(t *testing.T) {
			policy := noJitter(3, time.Millisecond)
			policy.RetryableStatuses = []int{400, 401, 403, 404, 500}

			doer := serving(stub{status: status, body: errorEnvelope(status, "failed").encode()})
			_, err := newTestClient(t, doer, nil, WithRetryPolicy(policy)).Nonprofits.Check(ctx, "411787097")

			var apiErr *APIError
			if !errors.As(err, &apiErr) || apiErr.Attempts != 1 || doer.calls() != 1 {
				t.Fatalf("err %v, requests %d", err, doer.calls())
			}
		})
	}

	t.Run("does not retry local validation errors", func(t *testing.T) {
		doer := serving(success)

		if _, err := newTestClient(t, doer, nil).Nonprofits.Check(ctx, "bad"); !errors.Is(err, ErrValidation) || doer.calls() != 0 {
			t.Fatalf("err %v, requests %d", err, doer.calls())
		}
	})

	t.Run("applies exponential backoff with a deterministic clock", func(t *testing.T) {
		clock := newClock()
		_, _ = newTestClient(t, serving(serverError), clock, WithRetryPolicy(noJitter(3, 100*time.Millisecond))).Nonprofits.Check(ctx, "411787097")

		if want := []time.Duration{100 * time.Millisecond, 200 * time.Millisecond, 400 * time.Millisecond}; !slices.Equal(clock.recorded(), want) {
			t.Errorf("delays = %v, want %v", clock.recorded(), want)
		}
	})

	t.Run("applies full jitter across the backoff window", func(t *testing.T) {
		clock := newClock()
		clock.jitter = 0.5
		policy := noJitter(2, 100*time.Millisecond)
		policy.Jitter = true

		_, _ = newTestClient(t, serving(serverError), clock, WithRetryPolicy(policy)).Nonprofits.Check(ctx, "411787097")

		if want := []time.Duration{50 * time.Millisecond, 100 * time.Millisecond}; !slices.Equal(clock.recorded(), want) {
			t.Errorf("delays = %v, want %v", clock.recorded(), want)
		}
	})

	t.Run("caps a single backoff delay at MaxDelay", func(t *testing.T) {
		clock := newClock()
		policy := noJitter(3, time.Second)
		policy.BackoffFactor = 10
		policy.MaxDelay = 2 * time.Second

		_, _ = newTestClient(t, serving(serverError), clock, WithRetryPolicy(policy)).Nonprofits.Check(ctx, "411787097")

		if want := []time.Duration{time.Second, 2 * time.Second, 2 * time.Second}; !slices.Equal(clock.recorded(), want) {
			t.Errorf("delays = %v, want %v", clock.recorded(), want)
		}
	})

	t.Run("accepts a per-request retry override", func(t *testing.T) {
		doer := serving(serverError)
		_, _ = newTestClient(t, doer, nil, WithoutRetries()).Nonprofits.Check(ctx, "411787097", WithMaxRetries(1))

		if doer.calls() != 2 {
			t.Errorf("requests = %d", doer.calls())
		}
	})
}

func TestRateLimiting(t *testing.T) {
	ctx := context.Background()
	limited := func(retryAfter string) stub {
		return stub{status: 429, body: errorEnvelope(429, "Too Many Requests").encode(), headers: map[string]string{"Retry-After": retryAfter}}
	}

	t.Run("maps 429 to the rate-limit category and exposes Retry-After", func(t *testing.T) {
		_, err := newTestClient(t, serving(limited("5")), nil, WithoutRetries()).Nonprofits.Check(ctx, "411787097")

		var apiErr *APIError
		if !errors.Is(err, ErrRateLimit) || !errors.As(err, &apiErr) || apiErr.RetryAfter == nil || *apiErr.RetryAfter != 5*time.Second {
			t.Fatalf("err = %v", err)
		}
	})

	t.Run("waits for the server Retry-After before falling back to backoff", func(t *testing.T) {
		clock := newClock()
		doer := serving(limited("7"), stub{body: envelope(wireNonprofit()).encode()})

		if _, err := newTestClient(t, doer, clock, WithRetryPolicy(noJitter(2, 100*time.Millisecond))).Nonprofits.Check(ctx, "411787097"); err != nil {
			t.Fatal(err)
		}

		if !slices.Equal(clock.recorded(), []time.Duration{7 * time.Second}) {
			t.Errorf("delays = %v", clock.recorded())
		}
	})

	t.Run("ignores Retry-After when the caller opts out", func(t *testing.T) {
		clock := newClock()
		policy := noJitter(2, 250*time.Millisecond)
		policy.RespectRetryAfter = false
		doer := serving(limited("7"), stub{body: envelope(wireNonprofit()).encode()})

		if _, err := newTestClient(t, doer, clock, WithRetryPolicy(policy)).Nonprofits.Check(ctx, "411787097"); err != nil {
			t.Fatal(err)
		}

		if !slices.Equal(clock.recorded(), []time.Duration{250 * time.Millisecond}) {
			t.Errorf("delays = %v", clock.recorded())
		}
	})

	t.Run("reads Retry-After as seconds or as an HTTP date", func(t *testing.T) {
		now := time.Date(2026, 1, 1, 12, 0, 0, 0, time.UTC)

		cases := map[string]time.Duration{
			"5":   5 * time.Second,
			"1.5": 1500 * time.Millisecond,
			" 0 ": 0,
			now.Add(4 * time.Second).Format(http.TimeFormat): 4 * time.Second,
			now.Add(-time.Hour).Format(http.TimeFormat):      0,
			// Not the HTTP form, but servers send it.
			now.Add(4 * time.Second).Format(time.RFC1123):  4 * time.Second,
			now.Add(4 * time.Second).Format(time.RFC1123Z): 4 * time.Second,
		}

		for header, want := range cases {
			if got := readRetryAfter(header, now); got == nil || *got != want {
				t.Errorf("readRetryAfter(%q) = %v, want %s", header, got, want)
			}
		}

		for _, header := range []string{"", "soon", "-5", "Inf", "NaN"} {
			if got := readRetryAfter(header, now); got != nil {
				t.Errorf("readRetryAfter(%q) = %s, want nil", header, *got)
			}
		}
	})

	t.Run("spaces requests when a client-side limit is configured", func(t *testing.T) {
		clock := newClock()
		client := newTestClient(t, serving(stub{body: envelope(wireNonprofit()).encode()}), clock, WithMaxRequestsPerSecond(2))

		for range 3 {
			if _, err := client.Nonprofits.Check(ctx, "411787097"); err != nil {
				t.Fatal(err)
			}
		}

		// The clock stands still, so each request waits for the whole schedule
		// accumulated so far. Against a real clock they would be 500ms apart.
		if want := []time.Duration{500 * time.Millisecond, time.Second}; !slices.Equal(clock.recorded(), want) {
			t.Errorf("delays = %v, want %v", clock.recorded(), want)
		}
	})

	t.Run("hands out distinct slots to concurrent callers", func(t *testing.T) {
		clock := newClock()
		client := newTestClient(t, serving(stub{body: envelope(wireNonprofit()).encode()}), clock, WithMaxRequestsPerSecond(4))

		var wg sync.WaitGroup

		for range 8 {
			wg.Add(1)

			go func() {
				defer wg.Done()

				if _, err := client.Nonprofits.Check(ctx, "411787097"); err != nil {
					t.Error(err)
				}
			}()
		}

		wg.Wait()

		delays := clock.recorded()
		slices.Sort(delays)

		var want []time.Duration
		for slot := 1; slot < 8; slot++ {
			want = append(want, time.Duration(slot)*250*time.Millisecond)
		}

		if !slices.Equal(delays, want) {
			t.Errorf("delays = %v, want %v", delays, want)
		}
	})

	t.Run("does not throttle when no client-side limit is set", func(t *testing.T) {
		clock := newClock()
		client := newTestClient(t, serving(stub{body: envelope(wireNonprofit()).encode()}), clock)

		for range 2 {
			_, _ = client.Nonprofits.Check(ctx, "411787097")
		}

		if len(clock.recorded()) != 0 {
			t.Errorf("delays = %v", clock.recorded())
		}
	})
}

func TestComputeRetryDelay(t *testing.T) {
	policy := noJitter(2, 500*time.Millisecond)
	random := func() float64 { return 1 }

	if got := computeRetryDelay(1, policy, ptr(3*time.Second), random); got != 3*time.Second {
		t.Errorf("with Retry-After: %s", got)
	}

	if got := computeRetryDelay(1, policy, nil, random); got != 500*time.Millisecond {
		t.Errorf("attempt 1: %s", got)
	}

	if got := computeRetryDelay(3, policy, nil, random); got != 2*time.Second {
		t.Errorf("attempt 3: %s", got)
	}
}
