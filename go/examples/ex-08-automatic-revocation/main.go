// EX-08 — The Automatic Revocation of Exemption list.
//
// An organization that fails to file for three consecutive years loses its
// exemption automatically. The revocation fields say so, and they say it
// independently of what the BMF and Publication 78 report.
//
//	go run ./examples/ex-08-automatic-revocation
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
		aroe := nonprofit.AROE()

		support.Heading(support.Text(nonprofit.OrganizationName) + " (" + ein + ")")

		if aroe == nil {
			support.Bullet("The API returned no revocation data at all.")

			continue
		}

		support.Field("revocation_code", aroe.RevocationCode)
		support.Field("  meaning", support.DescribeRevocationCode(aroe.RevocationCode))
		support.Field("revocation_date", aroe.RevocationDate)
		support.Field("reinstatement_date", aroe.ReinstatementDate)

		// The other sources agree here, and that is worth showing: a revocation
		// is visible in three places, and a workflow that reads only one of
		// them is one API change from missing it.
		support.Field("pub78_verified", nonprofit.Pub78Verified)
		support.Field("bmf_status", nonprofit.BMFStatus)
		support.Field("exempt_status_code", nonprofit.ExemptStatusCode)
		support.Field("  meaning", support.DescribeExemptStatus(nonprofit.ExemptStatusCode))
	}

	support.Note("A revocation date with no reinstatement date is the state worth acting on.\n" +
		"The next example shows why the reinstatement date is not optional reading.")
}
