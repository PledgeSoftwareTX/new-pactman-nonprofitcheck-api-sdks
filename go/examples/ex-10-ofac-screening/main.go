// EX-10 — OFAC screening.
//
// The API reports OFAC as a sentence, not a flag. This SDK does not invent a
// boolean from it, because deriving one means pattern-matching English that can
// be reworded at any time. This example does the pattern matching — in your
// code, where you can see it and own it — and shows the states it can end in,
// one of which is "I do not recognize this wording".
//
//	go run ./examples/ex-10-ofac-screening
package main

import (
	"context"
	"fmt"

	"github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks/go/examples/internal/support"
	"github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks/go/internal/mockapi"
)

func main() {
	ctx := context.Background()
	example := support.WithFixtures()

	defer example.Close()

	for _, ein := range []string{
		mockapi.PublicCharity,
		mockapi.OFACMatch,
		mockapi.OFACUnavailable,
		mockapi.SparseIdentity,
	} {
		result, err := example.Nonprofits().Check(ctx, ein)
		support.Must(err)

		nonprofit := result.Nonprofit
		ofac := nonprofit.OFAC()

		support.Heading(support.Text(nonprofit.OrganizationName) + " (" + ein + ")")

		returned := "nil — the source was not returned"
		if ofac != nil {
			returned = "returned"
		}

		support.Field("nonprofit.OFAC()", returned)
		support.Field("Fields.Has(\"ofac_status\")", nonprofit.Fields.Has("ofac_status"))
		support.Field("Fields.IsNull(\"ofac_status\")", nonprofit.Fields.IsNull("ofac_status"))
		support.Field("state", support.ReadOFAC(nonprofit))
		fmt.Println()
		fmt.Println("  " + support.Render(support.Present(nonprofit.Fields, "ofac_status")))
	}

	support.Note("Four states, and only one of them is a pass:\n" +
		"  NO_MATCH     — the API said the organization was not on the SDN list\n" +
		"  MATCH        — the API named a possible match, with a UID\n" +
		"  NULL         — the field came back with no value\n" +
		"  UNAVAILABLE  — the API returned no OFAC data at all\n\n" +
		"UNAVAILABLE and NULL are not clean results. They are the absence of a result,\n" +
		"and a screening workflow that treats them as clean has screened nothing.\n" +
		"UNRECOGNIZED — wording this reader does not know — belongs with them: route it\n" +
		"to a person rather than guessing.")
}
