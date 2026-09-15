// EX-11 — When the sources disagree.
//
// The BMF and Publication 78 are separate IRS extracts, published on different
// schedules. They can disagree, and the API says so with irs_bmf_pub78_conflict
// rather than picking a winner. Neither should this SDK, and neither should a
// workflow that silently prefers one.
//
//	go run ./examples/ex-11-source-conflict
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

	for _, ein := range []string{mockapi.PublicCharity, mockapi.Conflicted} {
		result, err := example.Nonprofits().Check(ctx, ein)
		support.Must(err)

		nonprofit := result.Nonprofit
		pub78 := nonprofit.Pub78()
		bmf := nonprofit.BMF()

		support.Heading(support.Text(nonprofit.OrganizationName) + " (" + ein + ")")
		support.Field("irs_bmf_pub78_conflict", nonprofit.IRSBMFPub78Conflict)

		if bmf == nil {
			support.Field("Business Master File", support.Absent)
		} else {
			support.Field("bmf_status", bmf.Status)
			support.Field("bmf_organization_name", bmf.OrganizationName)
			support.Field("most_recent_bmf", bmf.MostRecent)
		}

		if pub78 == nil {
			support.Field("Publication 78", support.Absent)
		} else {
			support.Field("pub78_verified", pub78.Verified)
			support.Field("pub78_organization_name", pub78.OrganizationName)
			support.Field("most_recent_pub78", pub78.MostRecent)
		}
	}

	support.Note("The second organization is exempt according to the BMF and unlisted according\n" +
		"to Publication 78. Both statements came from the IRS. The API flags the\n" +
		"disagreement; what to do about it is your policy:\n\n" +
		"  - a donation platform might accept the BMF and note the conflict\n" +
		"  - a DAF issuing a grant might hold it for review\n" +
		"  - a tax-receipt flow cares specifically about Publication 78\n\n" +
		"All three are right for their own obligations, which is exactly why the SDK\n" +
		"does not choose.")
}
