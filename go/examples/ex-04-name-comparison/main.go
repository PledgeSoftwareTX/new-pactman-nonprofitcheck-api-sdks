// EX-04 — Comparing an applicant's name against the record.
//
// The API returns three names for one organization: the BMF name, the
// Publication 78 name, and an "also known as". They disagree routinely, and none
// of them is wrong. Comparing an applicant's typed name against them is a
// customer policy question, which is why the comparison lives here and not in
// the SDK.
//
//	go run ./examples/ex-04-name-comparison ["Some Charity, Inc."]
package main

import (
	"context"
	"fmt"
	"os"

	"github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks/go/examples/internal/support"
	"github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks/go/internal/mockapi"
)

func main() {
	applicant := "Meals Today Example Nonprofit, Inc."
	if len(os.Args) > 1 {
		applicant = os.Args[1]
	}

	ctx := context.Background()
	example := support.WithFixtures()

	defer example.Close()

	result, err := example.Nonprofits().Check(ctx, mockapi.PublicCharity)
	support.Must(err)

	nonprofit := result.Nonprofit
	pub78 := nonprofit.Pub78()

	var pub78Name *string
	if pub78 != nil {
		pub78Name = pub78.OrganizationName
	}

	support.Heading("The names the API returned")
	support.Field("applicant typed", applicant)
	support.Field("organization_name", nonprofit.OrganizationName)
	support.Field("bmf_organization_name", nonprofit.BMFOrganizationName)
	support.Field("pub78_organization_name", pub78Name)
	support.Field("organization_name_aka", nonprofit.OrganizationNameAKA)

	support.Heading("Normalized for comparison")
	support.Field("applicant", support.NormalizeName(&applicant))
	support.Field("organization_name", support.NormalizeName(nonprofit.OrganizationName))

	support.Heading("How each one compares")

	candidates := []struct {
		label string
		value *string
	}{
		{"organization_name", nonprofit.OrganizationName},
		{"bmf_organization_name", nonprofit.BMFOrganizationName},
		{"pub78_organization_name", pub78Name},
		{"organization_name_aka", nonprofit.OrganizationNameAKA},
	}

	for _, candidate := range candidates {
		comparison := support.CompareNames(&applicant, candidate.value)
		summary := string(comparison)

		if overlap := support.WordOverlap(&applicant, candidate.value); overlap != nil {
			summary += fmt.Sprintf(" (word overlap %.2f)", *overlap)
		}

		support.Field(candidate.label, summary)
	}

	support.Note("A missing name is UNCOMPARABLE, never agreement — scoring an absent value\n" +
		"as a match is how a blank record passes a name check. And a name that differs\n" +
		"is not fraud: organizations rename, and IRS records lag. Route the\n" +
		"disagreement to a reviewer; do not fail the applicant on it.")
}
