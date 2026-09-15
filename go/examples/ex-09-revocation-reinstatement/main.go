// EX-09 — Revocation followed by reinstatement.
//
// A revoked organization can get its exemption back, and the record then carries
// both dates. Reading only revocation_date turns a currently-exempt charity into
// a rejection.
//
//	go run ./examples/ex-09-revocation-reinstatement
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

	for _, ein := range []string{mockapi.Revoked, mockapi.Reinstated} {
		result, err := example.Nonprofits().Check(ctx, ein)
		support.Must(err)

		nonprofit := result.Nonprofit
		aroe := nonprofit.AROE()

		if aroe == nil {
			support.Fail("Both fixtures should carry revocation data.")
		}

		support.Heading(support.Text(nonprofit.OrganizationName) + " (" + ein + ")")
		support.Field("revocation_date", aroe.RevocationDate)
		support.Field("reinstatement_date", aroe.ReinstatementDate)
		support.Field("revoked and not reinstated", support.RevokedAndNotReinstated(nonprofit))
		support.Field("revoked", daysAgo(support.AgeInDays(aroe.RevocationDate)))
		support.Field("reinstated", daysAgo(support.AgeInDays(aroe.ReinstatementDate)))

		// Both records carry a revocation date. Only one of them is still
		// revoked, and the fields that say so are the current status fields,
		// not the historical one.
		support.Field("pub78_verified", nonprofit.Pub78Verified)
		support.Field("bmf_status", nonprofit.BMFStatus)
	}

	support.Note("Both organizations were revoked. One of them is exempt today. A rule that\n" +
		"reads revocation_date alone rejects both — and the reinstated one has been back\n" +
		"in good standing for years. Read the pair, and prefer the current status fields\n" +
		"for the current question.")
}

func daysAgo(age *int64) any {
	if age == nil {
		return nil
	}

	return fmt.Sprintf("%d days ago", *age)
}
