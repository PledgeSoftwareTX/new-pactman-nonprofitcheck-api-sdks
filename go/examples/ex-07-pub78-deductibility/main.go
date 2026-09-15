// EX-07 — Publication 78 and deductibility limits.
//
// Publication 78 is what says a donation is deductible, and organization_types
// carries the limit that applies. A public charity and a private foundation
// differ here, and the difference is the donor's tax outcome.
//
//	go run ./examples/ex-07-pub78-deductibility
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
		mockapi.PrivateFoundation,
		mockapi.Revoked,
	} {
		result, err := example.Nonprofits().Check(ctx, ein)
		support.Must(err)

		nonprofit := result.Nonprofit
		pub78 := nonprofit.Pub78()

		support.Heading(support.Text(nonprofit.OrganizationName) + " (" + ein + ")")

		if pub78 == nil {
			support.Bullet("The API returned no Publication 78 data at all.")

			continue
		}

		support.Field("verified", pub78.Verified)
		support.Field("indicator", pub78.Indicator)
		support.Field("  meaning", support.DescribePub78Indicator(pub78.Indicator))
		support.Field("most_recent", pub78.MostRecent)
		support.Field("organization_types", pub78.OrganizationTypes)
		support.Field("  has(organization_types)", nonprofit.Fields.Has("organization_types"))
		support.Field("  returned as null", nonprofit.Fields.IsNull("organization_types"))

		for _, entry := range pub78.OrganizationTypes {
			if entry == nil {
				// An entry can itself be null. Read through it, not into it.
				support.Bullet("one entry was returned as null")

				continue
			}

			fmt.Println()
			support.Field("  limitation", entry.DeductibilityLimitation)
			support.Field("  status", entry.DeductibilityStatusDescription)
			support.Field("  text", truncate(entry.OrganizationType))
		}
	}

	support.Note("organization_types is empty for the revoked organization — the API sent null,\n" +
		"not an empty list. The slice is nil either way so ranging over it is always\n" +
		"safe; ask Fields.Has and Fields.IsNull when the difference matters.\n\n" +
		"Deductibility is the donor's tax question, not the charity's status. Read the\n" +
		"limit the API returned; do not infer one from the subsection.")
}

// truncate keeps the long deductibility sentence to one line.
func truncate(text *string) any {
	if text == nil {
		return nil
	}

	runes := []rune(*text)
	if len(runes) <= 72 {
		return *text
	}

	return string(runes[:69]) + "..."
}
