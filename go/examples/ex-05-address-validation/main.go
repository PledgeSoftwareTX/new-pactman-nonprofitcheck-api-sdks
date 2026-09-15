// EX-05 — Address validation.
//
// A non-null address field is not a usable address. This example runs three
// records through the same checks: one clean, one with several fields returned as
// null, and one where every component is present and they contradict each other.
//
//	go run ./examples/ex-05-address-validation
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
		mockapi.SparseIdentity,
		mockapi.InconsistentAddress,
	} {
		result, err := example.Nonprofits().Check(ctx, ein)
		support.Must(err)

		nonprofit := result.Nonprofit

		support.Heading(support.Text(nonprofit.OrganizationName) + " (" + ein + ")")

		for _, field := range []string{
			"address_line1", "address_line2", "city", "state", "state_name", "zip",
		} {
			support.Field(field, support.Present(nonprofit.Fields, field))
		}

		findings := support.AddressFindings(nonprofit)

		fmt.Println()

		if len(findings) == 0 {
			support.Bullet("nothing to report")
		}

		for _, finding := range findings {
			support.Bullet(finding)
		}
	}

	support.Note("The third record would pass any check that only asks whether the fields came\n" +
		"back non-null: every component is there. The state code, the spelled-out state\n" +
		"and the ZIP describe three different places, and address_line2 holds a\n" +
		"placeholder. Read the values, not just their presence.")
}
