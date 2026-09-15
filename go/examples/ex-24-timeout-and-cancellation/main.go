// EX-24 — Timeouts and cancellation.
//
// The timeout is always finite and there is no way to disable it. Cancellation
// is a different thing, and in Go it is the caller's context — which is why the
// SDK reports the two differently: a timeout means raise the budget or shed
// load, a cancellation means the caller went away.
//
//	go run ./examples/ex-24-timeout-and-cancellation
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
	// Retries off: a retried timeout would triple the wall clock and obscure
	// which attempt expired.
	example := support.WithFixtures(
		pactman.WithTimeout(30*time.Second),
		pactman.WithoutRetries(),
	)

	defer example.Close()

	support.Heading("A per-request timeout")
	support.Field("client timeout", example.Client.Timeout())

	started := time.Now()

	// The client's 30s budget stands; this one call gets 300ms.
	_, err := example.Nonprofits().Check(
		context.Background(), mockapi.Slow, pactman.WithTimeout(300*time.Millisecond))

	var timeout *pactman.TimeoutError

	if !errors.As(err, &timeout) {
		support.Fail("Expected a *pactman.TimeoutError, got %T: %v.", err, err)
	}

	support.Field("error type", fmt.Sprintf("%T", err))
	support.Field("category", timeout.Category())
	support.Field("Timeout", timeout.Timeout)
	support.Field("Attempts", timeout.Attempts)
	support.Field("wall clock", time.Since(started).Round(time.Millisecond))
	support.Field("client timeout after", example.Client.Timeout())

	// A timeout deliberately does not match context.DeadlineExceeded. The two
	// mean different things, and conflating them hides which side gave up.
	support.Field("errors.Is(err, pactman.ErrTimeout)", errors.Is(err, pactman.ErrTimeout))
	support.Field("errors.Is(err, context.DeadlineExceeded)",
		errors.Is(err, context.DeadlineExceeded))

	if errors.Is(err, context.DeadlineExceeded) {
		support.Fail("A TimeoutError should not match context.DeadlineExceeded.")
	}

	support.Heading("Cancelling an in-flight call")

	cancellable, cancel := context.WithCancel(context.Background())

	go func() {
		// Let the request actually get in flight, then give up on it.
		time.Sleep(150 * time.Millisecond)
		cancel()
	}()

	started = time.Now()
	_, err = example.Nonprofits().Check(cancellable, mockapi.Slow)

	cancel()

	var network *pactman.NetworkError

	if !errors.As(err, &network) {
		support.Fail("Expected a *pactman.NetworkError, got %T: %v.", err, err)
	}

	support.Field("error type", fmt.Sprintf("%T", err))
	support.Field("category", network.Category())
	support.Field("Attempts", network.Attempts)
	support.Field("wall clock", time.Since(started).Round(time.Millisecond))
	support.Field("errors.Is(err, context.Canceled)", errors.Is(err, context.Canceled))
	support.Field("errors.Is(err, pactman.ErrNetwork)", errors.Is(err, pactman.ErrNetwork))

	if !errors.Is(err, context.Canceled) {
		support.Fail("A cancelled call should unwrap to context.Canceled.")
	}

	support.Heading("The caller's own deadline")

	deadline, stop := context.WithTimeout(context.Background(), 250*time.Millisecond)
	defer stop()

	started = time.Now()
	_, err = example.Nonprofits().Check(deadline, mockapi.Slow)

	if !errors.As(err, &network) {
		support.Fail("Expected a *pactman.NetworkError, got %T: %v.", err, err)
	}

	support.Field("error type", fmt.Sprintf("%T", err))
	support.Field("wall clock", time.Since(started).Round(time.Millisecond))
	support.Field("errors.Is(err, context.DeadlineExceeded)",
		errors.Is(err, context.DeadlineExceeded))
	support.Field("errors.Is(err, pactman.ErrTimeout)", errors.Is(err, pactman.ErrTimeout))

	if errors.Is(err, pactman.ErrTimeout) {
		support.Fail("The caller's deadline is not the SDK's timeout.")
	}

	support.Note("Three ways for a call to stop early, and the SDK keeps them apart:\n\n" +
		"  *TimeoutError  — the per-attempt budget expired. Raise it, or shed load.\n" +
		"  *NetworkError  — the caller cancelled. Unwraps to context.Canceled.\n" +
		"  *NetworkError  — the caller's deadline passed. Unwraps to\n" +
		"                   context.DeadlineExceeded, and is not the SDK's timeout.\n\n" +
		"All three stop any planned retries, so nothing is left holding a socket and a\n" +
		"backoff schedule behind your back. A per-request WithTimeout overrides the\n" +
		"client's for that call only, and the client's own budget is unchanged after.")
}
