// EX-03 — Identity lookup.
//
// Reads the identity fields off a record, and shows the difference the SDK keeps
// and most callers lose: a field the API returned as null is not the same as a
// field the API did not return at all.
//
//	go run ./examples/ex-03-identity-lookup
package main

import (
	"context"

	"github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks/go/examples/internal/support"
	"github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks/go/internal/mockapi"
)

func main() {
	ctx := context.Background()
	example := support.WithFixtures()

	defer example.Close()

	for _, ein := range []string{mockapi.PublicCharity, mockapi.SparseIdentity} {
		result, err := example.Nonprofits().Check(ctx, ein)
		support.Must(err)

		nonprofit := result.Nonprofit
		if nonprofit == nil {
			support.Fail("No record for %s.", ein)
		}

		support.Heading("EIN " + ein)

		for _, field := range []string{
			"organization_name", "organization_name_aka", "address_line1",
			"address_line2", "city", "state", "state_name", "zip",
			"pub78_city", "pub78_state", "ofac_status",
		} {
			// Present reports <not returned> for a key the API omitted and
			// <null> for one it sent empty. Two different facts.
			support.Field(field, support.Present(nonprofit.Fields, field))
		}

		support.Field("HTTP status", result.Status)
		support.Field("Correlation id", result.RequestID)
	}

	support.Note("The second record is missing `ofac_status` entirely and returns null for\n" +
		"several identity fields. Fields.Has(name) is what separates the two, and the\n" +
		"distinction matters: \"the source reported nothing\" and \"the source reported\n" +
		"no value\" are different findings, and only one of them is about the\n" +
		"organization.\n\n" +
		"The typed fields read both as nil, which is the right default for code that\n" +
		"only wants a value. Reach for Fields when the absence itself is the answer.")
}
