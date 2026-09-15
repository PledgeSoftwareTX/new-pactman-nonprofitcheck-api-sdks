package pactman

import (
	"context"
	"errors"
	"io"
	"net/http"
	"strings"
	"testing"
	"time"
)

func TestTimeouts(t *testing.T) {
	ctx := context.Background()

	t.Run("documents a finite default timeout", func(t *testing.T) {
		client, err := NewClient(testAPIKey)
		if err != nil || client.Timeout() != DefaultTimeout || DefaultTimeout <= 0 {
			t.Fatalf("Timeout = %v, %v", client.Timeout(), err)
		}
	})

	t.Run("produces a timeout error when an attempt exceeds the timeout", func(t *testing.T) {
		client := newTestClient(t, serving(stub{hang: true}), nil, WithTimeout(10*time.Millisecond), WithoutRetries())

		_, err := client.Nonprofits.Check(ctx, "411787097")

		var terr *TimeoutError
		if !errors.As(err, &terr) || terr.Timeout != 10*time.Millisecond || terr.Category() != CategoryTimeout || terr.Attempts != 1 {
			t.Fatalf("err = %v", err)
		}

		if errors.Is(err, context.DeadlineExceeded) {
			t.Error("the SDK's own timeout matched context.DeadlineExceeded, which belongs to the caller")
		}
	})

	t.Run("lets a per-request timeout override the client's", func(t *testing.T) {
		client := newTestClient(t, serving(stub{hang: true}), nil, WithTimeout(5*time.Second), WithoutRetries())
		started := time.Now()

		_, err := client.Nonprofits.Check(ctx, "411787097", WithTimeout(15*time.Millisecond))

		var terr *TimeoutError
		if !errors.As(err, &terr) || terr.Timeout != 15*time.Millisecond || time.Since(started) > time.Second {
			t.Fatalf("err = %v after %s", err, time.Since(started))
		}
	})

	t.Run("covers reading the body, not only the headers", func(t *testing.T) {
		client := newTestClient(t, stallingBody{}, nil, WithTimeout(10*time.Millisecond), WithoutRetries())

		if _, err := client.Nonprofits.Check(ctx, "411787097"); !errors.Is(err, ErrTimeout) {
			t.Fatalf("err = %v", err)
		}
	})

	t.Run("retries a timeout when the retry policy allows it", func(t *testing.T) {
		doer := serving(stub{hang: true}, stub{body: envelope(wireNonprofit()).encode()})
		client := newTestClient(t, doer, nil, WithTimeout(10*time.Millisecond), WithRetryPolicy(noJitter(1, time.Millisecond)))

		result, err := client.Nonprofits.Check(ctx, "411787097")
		if err != nil || doer.calls() != 2 || str(result.Nonprofit.EIN) != "411787097" {
			t.Fatalf("err %v, requests %d", err, doer.calls())
		}
	})
}

func TestCancellation(t *testing.T) {
	t.Run("stops an in-flight request when the caller cancels, and does not retry it", func(t *testing.T) {
		ctx, cancel := context.WithCancel(context.Background())
		defer cancel()

		doer := serving(stub{hang: true})
		doer.onRequest = func(int) { cancel() }

		client := newTestClient(t, doer, nil, WithRetryPolicy(noJitter(3, time.Millisecond)))
		_, err := client.Nonprofits.Check(ctx, "411787097")

		var nerr *NetworkError
		if !errors.As(err, &nerr) || !errors.Is(err, context.Canceled) || nerr.Attempts != 1 {
			t.Fatalf("err = %v", err)
		}

		if !strings.Contains(err.Error(), "aborted") || doer.calls() != 1 {
			t.Errorf("message %q, requests %d", err.Error(), doer.calls())
		}
	})

	t.Run("does not start a request when the context has already ended", func(t *testing.T) {
		ctx, cancel := context.WithCancel(context.Background())
		cancel()

		doer := serving(stub{})
		_, err := newTestClient(t, doer, nil).Nonprofits.Check(ctx, "411787097")

		var nerr *NetworkError
		if !errors.As(err, &nerr) || nerr.Attempts != 0 || doer.calls() != 0 {
			t.Fatalf("err %v, requests %d", err, doer.calls())
		}
	})

	t.Run("stops planned retries once the caller cancels", func(t *testing.T) {
		ctx, cancel := context.WithCancel(context.Background())
		defer cancel()

		doer := serving(stub{status: 500, body: errorEnvelope(500, "failed").encode()})
		doer.onRequest = func(n int) {
			if n == 2 {
				cancel()
			}
		}

		_, err := newTestClient(t, doer, nil, WithRetryPolicy(noJitter(5, time.Millisecond))).Nonprofits.Check(ctx, "411787097")

		if !errors.Is(err, context.Canceled) || doer.calls() != 2 {
			t.Fatalf("err %v, requests %d", err, doer.calls())
		}
	})

	t.Run("reports the caller's deadline as the caller's, not as the SDK's timeout", func(t *testing.T) {
		ctx, cancel := context.WithTimeout(context.Background(), 20*time.Millisecond)
		defer cancel()

		client := newTestClient(t, serving(stub{hang: true}), nil, WithTimeout(5*time.Second))
		_, err := client.Nonprofits.Check(ctx, "411787097")

		if !errors.Is(err, ErrNetwork) || !errors.Is(err, context.DeadlineExceeded) || errors.Is(err, ErrTimeout) {
			t.Fatalf("err = %v", err)
		}
	})

	t.Run("the real sleep returns as soon as the context ends", func(t *testing.T) {
		ctx, cancel := context.WithCancel(context.Background())
		time.AfterFunc(5*time.Millisecond, cancel)
		started := time.Now()

		if err := sleepContext(ctx, time.Minute); !errors.Is(err, context.Canceled) || time.Since(started) > time.Second {
			t.Fatalf("err %v after %s", err, time.Since(started))
		}
	})
}

// stallingBody answers at once, then never finishes sending the body.
type stallingBody struct{}

func (stallingBody) Do(req *http.Request) (*http.Response, error) {
	return &http.Response{
		StatusCode: http.StatusOK,
		Header:     http.Header{"Content-Type": {"application/json"}},
		Body:       io.NopCloser(stalledReader{req.Context()}),
		Request:    req,
	}, nil
}

type stalledReader struct{ ctx context.Context }

func (r stalledReader) Read([]byte) (int, error) {
	<-r.ctx.Done()

	return 0, r.ctx.Err()
}
