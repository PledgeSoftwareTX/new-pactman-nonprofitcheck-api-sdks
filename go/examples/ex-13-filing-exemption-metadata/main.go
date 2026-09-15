// EX-13 — Filing and exemption metadata.
//
// The codes the API returns bare — filing requirement, exempt status — are the
// ones that need a local table. This example shows the table, and the two rules
// that keep one safe to own.
//
//	go run ./examples/ex-13-filing-exemption-metadata
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

	for _, ein := range []string{
		mockapi.PublicCharity,
		mockapi.PrivateFoundation,
		mockapi.Revoked,
	} {
		result, err := example.Nonprofits().Check(ctx, ein)
		support.Must(err)

		nonprofit := result.Nonprofit
		bmf := nonprofit.BMF()

		support.Heading(support.Text(nonprofit.OrganizationName) + " (" + ein + ")")

		if bmf == nil {
			support.Bullet("The API returned no Business Master File data at all.")

			continue
		}

		support.Field("filing_req_code", bmf.FilingReqCode)
		support.Field("  meaning", support.DescribeFilingRequirement(bmf.FilingReqCode))
		support.Field("exempt_status_code", bmf.ExemptStatusCode)
		support.Field("  meaning", support.DescribeExemptStatus(bmf.ExemptStatusCode))
		support.Field("group_exemption", bmf.GroupExemption)
		support.Field("ruling_month", bmf.RulingMonth)
		support.Field("ruling_year", bmf.RulingYear)
	}

	support.Heading("What an unknown code does")

	unknown := "99"

	support.Field("code \"99\"", support.DescribeFilingRequirement(&unknown))
	support.Field("code nil", support.DescribeFilingRequirement(nil))

	support.Note("Two rules make a local code table safe:\n\n" +
		"  1. An unknown code degrades to a sentence that keeps the code visible,\n" +
		"     never to nil and never to a wrong label. A value the IRS adds is then\n" +
		"     legible to whoever reads the output, without an SDK release.\n" +
		"  2. nil stays nil. Reporting \"unknown code\" for a field the API never sent\n" +
		"     invents a code, and someone downstream will investigate it.")
}
