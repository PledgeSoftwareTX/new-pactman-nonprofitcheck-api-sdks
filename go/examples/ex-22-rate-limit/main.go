// EX-22 — Rate limiting.
//
// HTTP 429 arrives as an *APIError with category rate_limit, carrying the
// server's Retry-After. With retries on, the SDK waits that long rather than
// applying its own backoff; with them off, the header is yours to act on.
//
//	go run ./examples/ex-22-rate-limit
package main

import (
	"context"
	"errors"
	"fmt"
	"sync"
	"time"

	"github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks/go/examples/internal/support"
	"github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks/go/internal/mockapi"
	"github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks/go/pactman"
)

func main() {
	ctx := context.Background()

	// Retrying is switched off so the 429 surfaces instead of being absorbed —
	// this example is about reading it.
	example := support.WithFixtures(pactman.WithoutRetries())

	defer example.Close()

	support.Heading("A 429, surfaced rather than retried")

	_, err := example.Nonprofits().Check(ctx, mockapi.RateLimited)

	if !errors.Is(err, pactman.ErrRateLimit) {
		support.Fail("Expected the API to report a rate limit, got %v.", err)
	}

	var apiErr *pactman.APIError

	if !errors.As(err, &apiErr) {
		support.Fail("Expected an *pactman.APIError, got %T.", err)
	}

	support.Field("error type", fmt.Sprintf("%T", err))
	support.Field("category", apiErr.Category())
	support.Field("status", apiErr.Status)
	support.Field("RetryAfter", apiErr.RetryAfter)
	support.Field("attempts", apiErr.Attempts)
	support.Field("requestId", apiErr.RequestID)

	if apiErr.Attempts != 1 {
		support.Fail("With retries off there should be one attempt, was %d.", apiErr.Attempts)
	}

	if apiErr.RetryAfter == nil {
		support.Fail("The server sent Retry-After; it should have been parsed.")
	}

	// With retries on, the SDK honours Retry-After before trying again. This
	// fixture answers 429 every time, so the attempts are what there is to see.
	support.Heading("With bounded retries, the wait is the server's number")

	retrying := support.WithFixtures(pactman.WithRetryPolicy(support.QuickRetries(2)))

	defer retrying.Close()

	started := time.Now()
	_, err = retrying.Nonprofits().Check(ctx, mockapi.RateLimited)

	if !errors.As(err, &apiErr) {
		support.Fail("Expected an *pactman.APIError, got %T.", err)
	}

	support.Field("attempts", apiErr.Attempts)
	support.Field("wall clock", time.Since(started).Round(time.Millisecond))

	if apiErr.Attempts != 3 {
		support.Fail("Two retries after the first attempt is three; was %d.", apiErr.Attempts)
	}

	// A courtesy ceiling and a bounded pool are the two things that keep a
	// batch job from finding the limit on the server's behalf.
	support.Heading("A client-side ceiling and a bounded pool")

	throttled := support.WithFixtures(pactman.WithMaxRequestsPerSecond(20))

	defer throttled.Close()

	const workers = 2

	eins := []string{
		mockapi.PublicCharity, mockapi.PublicCharitySecond, mockapi.PrivateFoundation,
		mockapi.PublicCharity, mockapi.PublicCharitySecond, mockapi.PrivateFoundation,
	}

	var (
		group     sync.WaitGroup
		mutex     sync.Mutex
		succeeded int
	)

	semaphore := make(chan struct{}, workers)
	started = time.Now()

	for _, ein := range eins {
		group.Add(1)

		go func(ein string) {
			defer group.Done()

			// Acquire a slot. Nothing beyond `workers` lookups is ever in
			// flight, whatever the length of the input.
			semaphore <- struct{}{}
			defer func() { <-semaphore }()

			if _, err := throttled.Nonprofits().Check(ctx, ein); err == nil {
				mutex.Lock()
				succeeded++
				mutex.Unlock()
			}
		}(ein)
	}

	group.Wait()

	support.Field("maxRequestsPerSecond", 20)
	support.Field("pool size", workers)
	support.Field("lookups", len(eins))
	support.Field("succeeded", succeeded)
	support.Field("wall clock", time.Since(started).Round(time.Millisecond))

	if succeeded != len(eins) {
		support.Fail("Every throttled lookup should have succeeded, %d did.", succeeded)
	}

	support.Note("The server's limits are authoritative and can change; a client-side ceiling is\n" +
		"a courtesy, not a guarantee, and it only spaces requests made through one\n" +
		"client. Share one client across your application, or each caller gets its own\n" +
		"throttle and the total is unbounded.\n\n" +
		"For volume, prefer one bulk request over fifty concurrent single checks.")
}
