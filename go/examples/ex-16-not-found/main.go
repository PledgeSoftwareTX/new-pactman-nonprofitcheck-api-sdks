// EX-16 — A well-formed EIN with no record.
//
// "Shaped like an EIN" and "an EIN the IRS has a record for" are different
// questions. The first is answered locally; only the second costs a request, and
// a miss is an ordinary outcome rather than a fault.
//
//	go run ./examples/ex-16-not-found
package main

import (
	"context"
	"errors"
	"fmt"

	"github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks/go/examples/internal/support"
	"github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks/go/internal/mockapi"
	"github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks/go/pactman"
)

func main() {
	ctx := context.Background()
	ein := mockapi.NoRecord

	support.Heading("Locally, this EIN is fine")
	support.Field("IsValidEIN", pactman.IsValidEIN(ein))

	normalized, err := pactman.NormalizeEIN(ein)
	support.Must(err)
	support.Field("NormalizeEIN", normalized)

	example := support.WithFixtures()

	defer example.Close()

	support.Heading("The API has no record for it")

	_, err = example.Nonprofits().Check(ctx, ein)

	if err == nil {
		support.Fail("Expected the lookup to report no record.")
	}

	if !errors.Is(err, pactman.ErrNotFound) {
		support.Fail("Expected a not_found error, got %v.", err)
	}

	var apiErr *pactman.APIError

	if !errors.As(err, &apiErr) {
		support.Fail("Expected an *pactman.APIError, got %T.", err)
	}

	support.Field("error type", fmt.Sprintf("%T", err))
	support.Field("category", apiErr.Category())
	support.Field("origin", apiErr.Origin())
	support.Field("status", apiErr.Status)
	support.Field("message", apiErr.Error())
	support.Field("requestId", apiErr.RequestID)
	support.Field("attempts", apiErr.Attempts)

	support.Heading("Branching on it")
	support.Field("errors.Is(err, pactman.ErrNotFound)", errors.Is(err, pactman.ErrNotFound))
	support.Field("errors.Is(err, pactman.ErrServer)", errors.Is(err, pactman.ErrServer))

	if apiErr.Attempts != 1 {
		support.Fail("A 404 should be attempted exactly once, was %d.", apiErr.Attempts)
	}

	support.Note("A single check with no record is an HTTP 404, and the SDK returns it as an\n" +
		"*APIError with category not_found — which is never retried, because the answer\n" +
		"will not change on a second attempt.\n\n" +
		"Bulk behaves differently on purpose: a batch where some EINs matched is a 200,\n" +
		"with the misses in NotFoundEINs. See ex-19.\n\n" +
		"No record is not evidence that an organization does not exist. It is the\n" +
		"absence of a record in the extracts behind this API.")
}
