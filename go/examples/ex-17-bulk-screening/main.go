// EX-17 — Screening a batch in one request.
//
// One bulk call instead of a loop of single checks: fewer round trips, one
// rate-limit interaction, and one place to read the usage counter.
//
//	go run ./examples/ex-17-bulk-screening
package main

import (
	"context"

	"github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks/go/examples/internal/support"
	"github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks/go/internal/mockapi"
	"github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks/go/pactman"
)

func main() {
	ctx := context.Background()
	eins := []string{
		mockapi.PublicCharity,
		mockapi.PublicCharitySecond,
		mockapi.Revoked,
		mockapi.OFACMatch,
		mockapi.Conflicted,
	}

	example := support.WithFixtures()

	defer example.Close()

	result, err := example.Nonprofits().CheckBulk(ctx, eins)
	support.Must(err)

	support.Heading("What came back")
	support.Field("requested", len(eins))
	support.Field("organizations", len(result.Organizations))
	support.Field("NotFoundEINs", result.NotFoundEINs)
	support.Field("CheckCount", result.CheckCount)

	// The response is not ordered to match the request, so pair by EIN. Never
	// by position.
	byEIN := map[string]*pactman.Nonprofit{}

	for _, organization := range result.Organizations {
		if organization.EIN != nil {
			byEIN[*organization.EIN] = organization
		}
	}

	for _, ein := range eins {
		organization, ok := byEIN[ein]

		if !ok {
			support.Heading(ein + " — no record")

			continue
		}

		support.Heading(ein + " — " + support.Text(organization.OrganizationName))

		findings := support.ScreeningFindings(organization)

		if len(findings) == 0 {
			support.Bullet("nothing to report")
		}

		for _, finding := range findings {
			support.Bullet(finding)
		}
	}

	support.Note("The findings above are what the API said. Not one of them is a decision: no\n" +
		"approved, no eligible, no safe. Which of them stops a payment is your policy,\n" +
		"and ex-26 to ex-30 show four workflows reading the same evidence and reaching\n" +
		"different, defensible conclusions.")
}
