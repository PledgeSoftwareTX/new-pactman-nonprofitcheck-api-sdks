// EX-25 — Raw access and forward compatibility.
//
// An API that adds a field should not break an SDK that has never heard of it.
// This example reads two records the typed fields cannot fully describe: one
// from a newer API version, and one from a deployment running ahead of
// production.
//
//	go run ./examples/ex-25-raw-and-forward-compat
package main

import (
	"context"
	"encoding/json"
	"fmt"

	"github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks/go/examples/internal/support"
	"github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks/go/internal/contract"
	"github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks/go/internal/mockapi"
)

func main() {
	ctx := context.Background()

	// The contract is what this package predicts a record contains. Anything
	// outside it is what this example is looking for.
	predicted, err := contract.Load()
	support.Must(err)

	example := support.WithFixtures()

	defer example.Close()

	for _, ein := range []string{mockapi.FutureFields, mockapi.PendingSourceFields} {
		result, err := example.Nonprofits().Check(ctx, ein)
		support.Must(err)

		nonprofit := result.Nonprofit

		support.Heading(support.Text(nonprofit.OrganizationName) + " (" + ein + ")")
		support.Field("fields returned", nonprofit.Fields.Len())
		support.Field("fields this SDK predicts", len(predicted.Nonprofit))

		unpredicted := []string{}

		for _, field := range nonprofit.Fields.Names() {
			if _, known := predicted.Nonprofit[field]; !known {
				unpredicted = append(unpredicted, field)
			}
		}

		fmt.Println()

		for _, field := range unpredicted {
			// Decoding did not fail, and the value did not vanish.
			support.Bullet(field + " = " + support.Render(support.Present(nonprofit.Fields, field)))
		}

		if len(unpredicted) == 0 {
			support.Fail("This fixture should carry fields outside the contract.")
		}
	}

	support.Heading("An unknown member inside a known object")

	future, err := example.Nonprofits().Check(ctx, mockapi.FutureFields)
	support.Must(err)

	for _, entry := range future.Nonprofit.OrganizationTypes {
		if entry == nil {
			continue
		}

		support.Field("deductibility_limitation", entry.DeductibilityLimitation)
		support.Field("deductibility_status_description", entry.DeductibilityStatusDescription)
		support.Field("future_deductibility_note",
			support.Present(entry.Fields, "future_deductibility_note"))
	}

	support.Heading("An enum value outside the documented set")
	support.Field("foundation_type_code", future.Nonprofit.FoundationTypeCode)
	support.Field("foundation_type_description", future.Nonprofit.FoundationTypeDescription)

	support.Heading("The whole envelope, unmodified")

	pending, err := example.Nonprofits().Check(ctx, mockapi.PendingSourceFields)
	support.Must(err)

	support.Field("envelope keys", pending.Raw.Fields.Names())

	// Marshalling the raw envelope returns the body exactly as it arrived,
	// which is what makes it usable as evidence.
	body, err := json.Marshal(pending.Raw)
	support.Must(err)

	support.Field("body bytes", len(body))

	support.Note("The second record is a deployment ahead of production: it carries the ten\n" +
		"source fields that are built but not yet released there. This SDK does not\n" +
		"declare them, on purpose — declaring a field production does not return would\n" +
		"promise something the API does not keep. They stay readable through Fields and\n" +
		"the raw envelope until a release declares them.\n\n" +
		"Nothing about an unpredicted field is an error. It is worth logging, because it\n" +
		"is how you find out the API moved before your SDK did.")
}
