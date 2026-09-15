// EX-12 — Foundation classification.
//
// Public charity or private foundation is the distinction that drives
// deductibility limits, excise taxes and expenditure responsibility. The API
// returns both the code and its description; prefer the description, because it
// comes from the source and changes with it.
//
//	go run ./examples/ex-12-foundation-classification
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

	for _, ein := range []string{mockapi.PublicCharity, mockapi.PrivateFoundation} {
		result, err := example.Nonprofits().Check(ctx, ein)
		support.Must(err)

		nonprofit := result.Nonprofit
		bmf := nonprofit.BMF()

		support.Heading(support.Text(nonprofit.OrganizationName) + " (" + ein + ")")

		if bmf == nil {
			support.Bullet("The API returned no Business Master File data at all.")

			continue
		}

		support.Field("subsection", bmf.Subsection)
		support.Field("subsection_description", bmf.SubsectionDescription)
		support.Field("foundation_code", bmf.FoundationCode)
		support.Field("foundation_code_description", bmf.FoundationCodeDescription)
		support.Field("foundation_type_code", bmf.FoundationTypeCode)
		support.Field("foundation_type_description", bmf.FoundationTypeDescription)
		support.Field("foundation_509a_status", bmf.Foundation509aStatus)
	}

	support.Note("Read the *_description fields rather than mapping the codes yourself. They\n" +
		"arrive from the IRS extract, so a classification the IRS adds is described\n" +
		"correctly the day it appears — a local table would need an SDK release, and in\n" +
		"the meantime would either say nothing or say the wrong thing.\n\n" +
		"Both codes and descriptions can be null. A missing classification is not a\n" +
		"public charity by default.")
}
