// EX-19 — Partial success in a batch.
//
// A batch where some EINs matched is a successful response with the misses listed
// inside it — not an error. Code that only checks err will process the matches
// and never notice the rest.
//
//	go run ./examples/ex-19-bulk-partial-success
package main

import (
	"context"

	"github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks/go/examples/internal/support"
	"github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks/go/internal/mockapi"
)

func main() {
	ctx := context.Background()
	eins := []string{
		mockapi.PublicCharity,
		mockapi.NoRecord,
		mockapi.PublicCharitySecond,
	}

	example := support.WithFixtures()

	defer example.Close()

	result, err := example.Nonprofits().CheckBulk(ctx, eins)

	// The miss is not an error. err is nil here.
	support.Must(err)

	support.Heading("The response")
	support.Field("err", err)
	support.Field("HTTP status", result.Status)
	support.Field("organizations", len(result.Organizations))
	support.Field("NotFoundEINs", result.NotFoundEINs)
	support.Field("Errors", len(result.Errors))
	support.Field("CheckCount", result.CheckCount)

	if result.Status != 200 {
		support.Fail("Partial success should be an HTTP 200, was %d.", result.Status)
	}

	if len(result.NotFoundEINs) == 0 {
		support.Fail("The missing EIN should have been reported.")
	}

	support.Heading("What the errors list carried")

	for _, detail := range result.Errors {
		support.Field("resource", detail.Resource)
		support.Field("code", detail.Code)
		support.Field("reason", detail.Reason)
		support.Field("eins", detail.EINs)
	}

	support.Heading("Matched")

	for _, organization := range result.Organizations {
		support.Bullet(support.Text(organization.EIN) + " — " +
			support.Text(organization.OrganizationName))
	}

	support.Heading("Reconciling against the input")

	found := map[string]bool{}

	for _, organization := range result.Organizations {
		if organization.EIN != nil {
			found[*organization.EIN] = true
		}
	}

	for _, ein := range eins {
		outcome := "matched"
		if !found[ein] {
			outcome = "no record"
		}

		support.Field(ein, outcome)
	}

	support.Note("Three EINs, two records, one 200. NotFoundEINs is collected from the\n" +
		"envelope's errors list, so the misses are as visible as the matches — but only\n" +
		"if you read them. Reconciling every input against the response is the habit\n" +
		"that catches the row nobody looked at.\n\n" +
		"Only matched EINs are billed, which is why CheckCount rose by two and not by\n" +
		"three — and why usage cannot be reconstructed from the size of the batch you\n" +
		"sent.")
}
