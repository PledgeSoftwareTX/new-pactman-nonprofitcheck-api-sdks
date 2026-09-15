// EX-15 — A malformed EIN never reaches the API.
//
// Local validation is not a convenience. Every request is billable, and a
// request that cannot succeed should not be one of them. This example proves it
// with an HTTP client that counts: nothing is sent.
//
//	go run ./examples/ex-15-malformed-ein
package main

import (
	"context"
	"errors"
	"fmt"
	"net/http"

	"github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks/go/examples/internal/support"
	"github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks/go/pactman"
)

// counting wraps an HTTP client and records how many requests were actually
// made. It is the only way to demonstrate a negative: that a rejected EIN cost
// nothing.
type counting struct {
	requests int
	inner    *http.Client
}

func (c *counting) Do(request *http.Request) (*http.Response, error) {
	c.requests++

	return c.inner.Do(request)
}

func main() {
	ctx := context.Background()
	counter := &counting{inner: &http.Client{}}

	// The base URL is deliberately somewhere nothing is listening: if local
	// validation ever stopped working, this example would fail loudly rather
	// than quietly billing a real request.
	client, err := pactman.NewClient(
		"unused-because-nothing-is-sent",
		pactman.WithBaseURL("http://127.0.0.1:1"),
		pactman.WithHTTPClient(counter),
	)
	support.Must(err)

	support.Heading("A single malformed EIN")

	_, err = client.Nonprofits.Check(ctx, "4117870")

	if err == nil {
		support.Fail("The malformed EIN should have been rejected.")
	}

	var validation *pactman.ValidationError

	if !errors.As(err, &validation) {
		support.Fail("Expected a *pactman.ValidationError, got %T.", err)
	}

	support.Field("error type", fmt.Sprintf("%T", err))
	support.Field("category", validation.Category())
	support.Field("origin", validation.Origin())
	support.Field("message", validation.Error())
	support.Field("requests sent", counter.requests)

	support.Heading("A batch with two bad rows")

	_, err = client.Nonprofits.CheckBulk(ctx, []string{"411787097", "nope", "996589560", "1234"})

	if err == nil {
		support.Fail("The batch should have been rejected.")
	}

	if !errors.As(err, &validation) {
		support.Fail("Expected a *pactman.ValidationError, got %T.", err)
	}

	support.Field("message", validation.Error())
	fmt.Println()

	for _, issue := range validation.Issues {
		support.Bullet(fmt.Sprintf("index %d (%q): %s", issue.Index, issue.Value, issue.Message))

		if issue.Index < 0 {
			support.Fail("A batch issue should name the row it came from.")
		}
	}

	support.Heading("Nothing was sent")
	support.Field("requests sent", counter.requests)

	if counter.requests != 0 {
		support.Fail("A locally rejected EIN must not reach the API; %d request(s) were sent.",
			counter.requests)
	}

	support.Note("origin is what separates these from an API-side rejection. A\n" +
		"*ValidationError with origin \"local\" means nothing was sent and nothing was\n" +
		"billed; an *APIError with category bad_request and origin \"api\" means the API\n" +
		"looked at the request and refused it. Retrying the first is pointless until the\n" +
		"input changes, which is why neither is ever retried.")
}
