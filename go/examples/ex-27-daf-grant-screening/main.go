// EX-27 — Donor-advised fund grant screening.
//
// A DAF has obligations a donation platform does not. A grant to a private
// foundation triggers expenditure responsibility; an OFAC finding stops the grant
// outright; and "the API returned no OFAC data" is not a clean screen.
//
// Same API responses as ex-26, stricter policy. Both are correct.
//
//	go run ./examples/ex-27-daf-grant-screening
package main

import (
	"context"
	"strings"

	"github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks/go/examples/internal/support"
	"github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks/go/internal/mockapi"
	"github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks/go/pactman"
)

func main() {
	ctx := context.Background()
	candidates := []string{
		mockapi.PublicCharity,
		mockapi.PrivateFoundation,
		mockapi.OFACMatch,
		mockapi.OFACUnavailable,
		mockapi.Conflicted,
	}

	example := support.WithFixtures()

	defer example.Close()

	result, err := example.Nonprofits().CheckBulk(ctx, candidates)
	support.Must(err)

	byEIN := map[string]*pactman.Nonprofit{}

	for _, organization := range result.Organizations {
		if organization.EIN != nil {
			byEIN[*organization.EIN] = organization
		}
	}

	for _, ein := range candidates {
		nonprofit, ok := byEIN[ein]

		if !ok {
			support.Heading(ein + " — no record")
			support.Field("decision", "HOLD — no record to screen against")

			continue
		}

		support.Heading(support.Text(nonprofit.OrganizationName) + " (" + ein + ")")

		ofac := support.ReadOFAC(nonprofit)
		bmf := nonprofit.BMF()

		privateFoundation := bmf != nil && bmf.SubsectionDescription != nil &&
			strings.Contains(strings.ToLower(*bmf.SubsectionDescription), "private foundation")

		support.Field("ofac", ofac)
		support.Field("pub78_verified", nonprofit.Pub78Verified)

		if bmf == nil {
			support.Field("classification", nil)
		} else {
			support.Field("classification", bmf.SubsectionDescription)
		}

		support.Field("bmf/pub78 conflict", nonprofit.IRSBMFPub78Conflict)

		// The DAF's policy. Anything other than an affirmative OFAC no-match
		// stops the grant, because an unscreened grant and a screened one are
		// not the same thing.
		var decision string

		switch {
		case ofac != support.OFACNoMatch:
			decision = "STOP — OFAC screening did not return an affirmative no-match"
		case nonprofit.Pub78Verified == nil || !*nonprofit.Pub78Verified:
			decision = "STOP — not listed in Publication 78"
		case nonprofit.IRSBMFPub78Conflict != nil && *nonprofit.IRSBMFPub78Conflict:
			decision = "HOLD — the IRS sources disagree"
		case privateFoundation:
			decision = "HOLD — expenditure responsibility applies to a private foundation"
		default:
			decision = "PROCEED under this fund's policy"
		}

		support.Field("decision", decision)
	}

	support.Note("Two organizations here have no OFAC match. One of them returned the field\n" +
		"with no value, and this fund stops on it — because \"we did not screen\" and \"we\n" +
		"screened and found nothing\" are different sentences to write in a file that a\n" +
		"regulator may later read.\n\n" +
		"Compare with ex-26: a donation platform reading these same responses reasonably\n" +
		"proceeds where this fund holds.")
}
