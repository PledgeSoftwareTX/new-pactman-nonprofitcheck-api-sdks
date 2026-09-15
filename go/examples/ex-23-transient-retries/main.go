// EX-23 — Retrying transient failures.
//
// A 503 that clears on the next attempt should not reach your error handler. A
// rejected key should reach it immediately, because it will still be rejected on
// the third attempt.
//
//	go run ./examples/ex-23-transient-retries
package main

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks/go/examples/internal/support"
	"github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks/go/internal/mockapi"
	"github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks/go/pactman"
)

func main() {
	ctx := context.Background()

	// Short delays so the example does not spend the default backoff waiting.
	// The defaults — 500ms growing by two, with full jitter — are right for
	// production.
	example := support.WithFixtures(pactman.WithRetryPolicy(support.QuickRetries(3)))

	defer example.Close()

	support.Heading("Two 503s, then a success")

	started := time.Now()
	result, err := example.Nonprofits().Check(ctx, mockapi.TransientFailure)
	support.Must(err)

	support.Field("organization", result.Nonprofit.OrganizationName)
	support.Field("HTTP status", result.Status)
	support.Field("wall clock", time.Since(started).Round(time.Millisecond))
	support.Bullet("The caller never saw the two failures.")

	support.Heading("A rejected key is not retried")

	rejected, err := pactman.NewClient(
		"not-the-right-key",
		pactman.WithBaseURL(example.Client.BaseURL()),
		pactman.WithRetryPolicy(support.QuickRetries(3)),
	)
	support.Must(err)

	started = time.Now()
	_, err = rejected.Nonprofits.Check(ctx, mockapi.PublicCharity)

	if !errors.Is(err, pactman.ErrAuthentication) {
		support.Fail("Expected the key to be rejected, got %v.", err)
	}

	var apiErr *pactman.APIError

	if !errors.As(err, &apiErr) {
		support.Fail("Expected an *pactman.APIError, got %T.", err)
	}

	support.Field("error type", fmt.Sprintf("%T", err))
	support.Field("category", apiErr.Category())
	support.Field("attempts", apiErr.Attempts)
	support.Field("wall clock", time.Since(started).Round(time.Millisecond))

	if apiErr.Attempts != 1 {
		support.Fail("A 401 should be attempted exactly once, was %d.", apiErr.Attempts)
	}

	support.Heading("The policy, as configured")

	policy := example.Client.RetryPolicy()

	support.Field("MaxRetries", policy.MaxRetries)
	support.Field("InitialDelay", policy.InitialDelay)
	support.Field("MaxDelay", policy.MaxDelay)
	support.Field("BackoffFactor", policy.BackoffFactor)
	support.Field("Jitter", policy.Jitter)
	support.Field("RetryableStatuses", fmt.Sprint(policy.RetryableStatuses))
	support.Field("RespectRetryAfter", policy.RespectRetryAfter)

	support.Note("Retried: 429, 500, 502, 503, 504, and transient network failures.\n" +
		"Never retried: 400, 401, 403, 404 — whatever RetryableStatuses says.\n\n" +
		"The reason is quota. A request that cannot succeed on the first attempt cannot\n" +
		"succeed on the third either, and each one costs. Backoff is jittered by default\n" +
		"so that clients failing together do not retry in lockstep and turn a blip into\n" +
		"an outage.")
}
