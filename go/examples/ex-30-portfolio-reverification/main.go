// EX-30 — Re-verifying a whole portfolio.
//
// A periodic sweep over every organization you have a relationship with. The
// output is a work queue, not a set of decisions: what changed, what is now
// questionable, and what could not be checked.
//
//	go run ./examples/ex-30-portfolio-reverification
package main

import (
	"context"

	"github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks/go/examples/internal/support"
	"github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks/go/internal/mockapi"
	"github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks/go/pactman"
)

// The portfolio, and what the last sweep concluded about each row. A slice
// rather than a map: the order of the sweep should be reproducible.
var portfolio = []struct {
	ein       string
	lastSweep string
}{
	{mockapi.PublicCharity, "clear"},
	// Flagged by the last sweep. Whatever the finding was, it is gone now —
	// which is a change this sweep has to report just as loudly as a new one.
	{mockapi.PublicCharitySecond, "findings"},
	{mockapi.Revoked, "clear"},
	{mockapi.OFACMatch, "clear"},
	{mockapi.Reinstated, "findings"},
	{mockapi.StaleData, "clear"},
	{mockapi.NoRecord, "clear"},
}

func main() {
	ctx := context.Background()

	// A courtesy ceiling: a sweep is background work and should not spend the
	// rate limit a customer-facing path needs.
	example := support.WithFixtures(pactman.WithMaxRequestsPerSecond(5))

	defer example.Close()

	eins := make([]string, 0, len(portfolio))
	lastKnown := map[string]string{}

	for _, entry := range portfolio {
		eins = append(eins, entry.ein)
		lastKnown[entry.ein] = entry.lastSweep
	}

	var changed, unverifiable []string

	checked := 0

	// One bulk request per batch, rather than a request per row.
	for start := 0; start < len(eins); start += pactman.MaxBulkEINs {
		end := start + pactman.MaxBulkEINs
		if end > len(eins) {
			end = len(eins)
		}

		chunk := eins[start:end]

		result, err := example.Nonprofits().CheckBulk(ctx, chunk)
		support.Must(err)

		byEIN := map[string]*pactman.Nonprofit{}

		for _, organization := range result.Organizations {
			if organization.EIN != nil {
				byEIN[*organization.EIN] = organization
			}
		}

		for _, ein := range chunk {
			nonprofit, ok := byEIN[ein]

			if !ok {
				unverifiable = append(unverifiable, ein)

				continue
			}

			checked++

			findings := support.ScreeningFindings(nonprofit)

			now := "clear"
			if len(findings) > 0 {
				now = "findings"
			}

			support.Heading(support.Text(nonprofit.OrganizationName) + " (" + ein + ")")
			support.Field("last sweep", lastKnown[ein])
			support.Field("this sweep", now)

			for _, finding := range findings {
				support.Bullet(finding)
			}

			if now != lastKnown[ein] {
				changed = append(changed, ein)
				support.Field("queue", "CHANGED — needs a look")
			}
		}
	}

	support.Heading("Sweep summary")
	support.Field("portfolio", len(eins))
	support.Field("checked", checked)
	support.Field("changed since last sweep", changed)
	support.Field("could not be verified", unverifiable)

	if len(changed) != 3 {
		support.Fail("Three rows should have changed, %d did.", len(changed))
	}

	if len(unverifiable) != 1 {
		support.Fail("One row should have been unverifiable, %d were.", len(unverifiable))
	}

	support.Note("Rows changed in both directions: two picked up findings and one cleared\n" +
		"them. A sweep that only reported new problems would miss the third, and someone\n" +
		"would keep treating a resolved flag as live.\n\n" +
		"The EIN with no record is neither clear nor a finding — it is unverifiable, and\n" +
		"it belongs in its own bucket. Folding it into either of the other two reports\n" +
		"something the API never said.")
}
