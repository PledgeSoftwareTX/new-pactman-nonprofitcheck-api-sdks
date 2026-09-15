// EX-21 — Usage tracking.
//
// CheckCount is a running total for the billing cycle, not the size of the
// request that returned it. Reading it as a per-request cost is the single most
// common way to misreport usage.
//
//	go run ./examples/ex-21-usage-tracking
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

	first, err := example.Nonprofits().Check(ctx, mockapi.PublicCharity)
	support.Must(err)

	support.Heading("A single check")
	support.Field("CheckCount", first.CheckCount)
	support.Field("TimeTaken", first.TimeTaken)

	batch, err := example.Nonprofits().CheckBulk(ctx, []string{
		mockapi.PublicCharity,
		mockapi.PublicCharitySecond,
		mockapi.PrivateFoundation,
		mockapi.NoRecord,
	})
	support.Must(err)

	support.Heading("A batch of four, one of which has no record")
	support.Field("EINs sent", 4)
	support.Field("organizations returned", len(batch.Organizations))
	support.Field("NotFoundEINs", batch.NotFoundEINs)
	support.Field("CheckCount", batch.CheckCount)

	support.Heading("What the batch actually consumed")
	support.Field("count before", first.CheckCount)
	support.Field("count after", batch.CheckCount)

	if first.CheckCount == nil || batch.CheckCount == nil {
		support.Field("delta", nil)
		support.Note("This deployment did not report nonprofit_check_count.")

		return
	}

	delta := *batch.CheckCount - *first.CheckCount

	support.Field("delta", delta)

	if delta != 3 {
		support.Fail("Three of the four EINs were billable; the counter moved by %d.", delta)
	}

	support.Note("Four EINs went out and the counter moved by three, because the EIN with no\n" +
		"record was not billed. Two consequences:\n\n" +
		"  - the size of your batch is not its cost\n" +
		"  - a delta between two responses is, and it is the only number that is\n\n" +
		"The counter resets when a new billing cycle begins, so a delta across that\n" +
		"boundary is meaningless. Read the value the API reports rather than keeping\n" +
		"your own running total.")
}
