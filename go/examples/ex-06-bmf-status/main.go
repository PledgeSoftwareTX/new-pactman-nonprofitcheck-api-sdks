// EX-06 — Reading the IRS Business Master File finding.
//
// bmf_status is the closest thing the API has to "the IRS lists this
// organization as exempt". It is still one source among four, and it has three
// states, not two.
//
//	go run ./examples/ex-06-bmf-status
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

	for _, ein := range []string{mockapi.PublicCharity, mockapi.Revoked} {
		result, err := example.Nonprofits().Check(ctx, ein)
		support.Must(err)

		nonprofit := result.Nonprofit
		bmf := nonprofit.BMF()

		support.Heading(support.Text(nonprofit.OrganizationName) + " (" + ein + ")")

		if bmf == nil {
			support.Bullet("The API returned no Business Master File data at all.")

			continue
		}

		support.Field("status", bmf.Status)
		support.Field("subsection", bmf.Subsection)
		support.Field("subsection_description", bmf.SubsectionDescription)
		support.Field("exempt_status_code", bmf.ExemptStatusCode)
		support.Field("  meaning", support.DescribeExemptStatus(bmf.ExemptStatusCode))
		support.Field("ruling", support.Text(bmf.RulingMonth)+"/"+support.Text(bmf.RulingYear))
		support.Field("most_recent_bmf", bmf.MostRecent)
	}

	support.Note("bmf_status has three states, and a boolean cast collapses one of them:\n" +
		"  true  — the BMF lists the organization as exempt\n" +
		"  false — the BMF has a record and it is not exempt\n" +
		"  null  — the BMF said nothing either way\n" +
		"Only the first is a positive finding. Treating null as false invents a\n" +
		"negative the IRS never gave you, which is why the field is a *bool and not a\n" +
		"bool.")
}
