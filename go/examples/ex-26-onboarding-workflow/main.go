// EX-26 — Onboarding a nonprofit to a giving platform.
//
// An applicant types a name and an EIN. This workflow decides one thing: whether
// a human needs to look at the application. It never decides whether the
// organization is legitimate.
//
//	go run ./examples/ex-26-onboarding-workflow
package main

import (
	"context"
	"errors"

	"github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks/go/examples/internal/support"
	"github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks/go/internal/mockapi"
	"github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks/go/pactman"
)

// One applicant, as they typed it.
type applicant struct {
	ein  string
	name string
}

func main() {
	ctx := context.Background()
	applicants := []applicant{
		{mockapi.PublicCharity, "Meals Today Example Nonprofit Inc."},
		{mockapi.Revoked, "Lapsed Filings Example Society"},
		{mockapi.InconsistentAddress, "Harbour Light Example Alliance"},
		{mockapi.NoRecord, "Brand New Example Charity"},
	}

	example := support.WithFixtures()

	defer example.Close()

	for _, entry := range applicants {
		support.Heading(entry.name + " (" + entry.ein + ")")

		result, err := example.Nonprofits().Check(ctx, entry.ein)

		if errors.Is(err, pactman.ErrNotFound) {
			support.Bullet("No IRS record for this EIN.")
			support.Field("routing", "MANUAL REVIEW — cannot verify without a record")

			continue
		}

		support.Must(err)

		nonprofit := result.Nonprofit
		typedName := entry.name

		nameCheck := support.CompareNames(&typedName, nonprofit.OrganizationName)
		screening := support.ScreeningFindings(nonprofit)
		address := support.AddressFindings(nonprofit)

		support.Field("IRS name", nonprofit.OrganizationName)
		support.Field("name comparison", nameCheck)

		for _, finding := range screening {
			support.Bullet(finding)
		}

		for _, finding := range address {
			support.Bullet(finding)
		}

		// The policy, stated in one place so that it can be argued with.
		needsReview := nameCheck != support.Agree ||
			len(screening) > 0 ||
			len(address) > 0

		routing := "PROCEED under this platform's policy"
		if needsReview {
			routing = "MANUAL REVIEW"
		}

		support.Field("routing", routing)
	}

	support.Note("Every branch above is this platform's policy, not the SDK's and not the\n" +
		"API's. A different platform reading identical responses would route them\n" +
		"differently and would also be right.\n\n" +
		"Note what the workflow does with a missing record: it asks for a human, not a\n" +
		"rejection. Absence of a record is not evidence of anything.")
}
