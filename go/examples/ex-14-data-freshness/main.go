// EX-14 — How fresh the underlying data is.
//
// Every finding on a record is as old as the extract it came from. A clean
// result from a two-year-old extract is a clean result about two years ago,
// which is a different statement from the one most workflows think they are
// making.
//
//	go run ./examples/ex-14-data-freshness
package main

import (
	"context"
	"fmt"

	"github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks/go/examples/internal/support"
	"github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks/go/internal/mockapi"
)

// A re-review threshold. Yours belongs in your policy, not in the SDK.
const staleAfterDays = 180

func main() {
	ctx := context.Background()
	example := support.WithFixtures()

	defer example.Close()

	for _, ein := range []string{mockapi.PublicCharity, mockapi.StaleData} {
		result, err := example.Nonprofits().Check(ctx, ein)
		support.Must(err)

		nonprofit := result.Nonprofit

		support.Heading(support.Text(nonprofit.OrganizationName) + " (" + ein + ")")

		sources := []struct {
			label string
			value *string
		}{
			{"most_recent_bmf", nonprofit.MostRecentBMF},
			{"most_recent_pub78", nonprofit.MostRecentPub78},
			{"organization_info_last_modified", nonprofit.OrganizationInfoLastModified},
			{"report_date", nonprofit.ReportDate},
		}

		for _, source := range sources {
			rendered := support.Render(source.value)

			if age := support.AgeInDays(source.value); age != nil {
				rendered += fmt.Sprintf("  (%d days ago)", *age)
			}

			support.Field(source.label, rendered)
		}

		oldest := support.OldestSourceAgeDays(nonprofit)

		fmt.Println()

		if oldest == nil {
			support.Field("oldest source", nil)
			support.Field(fmt.Sprintf("past a %d-day rule", staleAfterDays), "unknown")

			continue
		}

		support.Field("oldest source", fmt.Sprintf("%d days", *oldest))
		support.Field(fmt.Sprintf("past a %d-day rule", staleAfterDays), *oldest > staleAfterDays)
	}

	support.Note("The second organization has nothing adverse on its record and every source is\n" +
		"well over a year old. Both facts are true, and a workflow that reads only the\n" +
		"first has re-verified nothing.\n\n" +
		"The API formats dates for display, not for machines. Parsing them means\n" +
		"assuming a locale and a time zone, which is why the SDK hands them back as\n" +
		"strings and leaves the assumption to code like this, where it is visible. An\n" +
		"unparseable date reads as \"I do not know\", never as today.")
}
