// EX-18 — Ordering and duplicates in a bulk request.
//
// The one pairing rule that always holds: index the response by EIN. The API
// matches by set membership, so it neither preserves your order nor returns a
// repeated EIN twice.
//
//	go run ./examples/ex-18-bulk-order-and-duplicates
package main

import (
	"context"

	"github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks/go/examples/internal/support"
	"github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks/go/internal/mockapi"
	"github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks/go/pactman"
)

func main() {
	ctx := context.Background()
	requested := []string{
		mockapi.PublicCharitySecond,
		mockapi.PublicCharity,
		mockapi.PublicCharitySecond,
	}

	example := support.WithFixtures()

	defer example.Close()

	support.Heading("Duplicates are sent as supplied")

	asSupplied, err := example.Nonprofits().CheckBulk(ctx, requested)
	support.Must(err)

	support.Field("requested", requested)
	support.Field("organizations returned", len(asSupplied.Organizations))

	returned := []string{}

	for _, organization := range asSupplied.Organizations {
		returned = append(returned, support.Text(organization.EIN))
	}

	support.Field("EINs returned", returned)

	if len(returned) == len(requested) {
		support.Fail("The API should have collapsed the repeated EIN into one record.")
	}

	support.Heading("Deduplicating before sending")

	deduped, err := example.Nonprofits().CheckBulk(ctx, requested, pactman.WithDedupe())
	support.Must(err)

	support.Field("organizations returned", len(deduped.Organizations))

	support.Note("Three EINs went out and two records came back, because the API matches by set\n" +
		"membership. Pairing the response with the request by position would have\n" +
		"attributed the second organization's findings to the third row.\n\n" +
		"Duplicates are sent as supplied by default, because each one is billable and\n" +
		"silently dropping them would misreport what was checked. WithDedupe() is the\n" +
		"opt-in, and it is the right call when your input is a CSV nobody cleaned.")
}
