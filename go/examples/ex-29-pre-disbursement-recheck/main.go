// EX-29 — Re-checking immediately before money moves.
//
// A verification done at onboarding is a statement about the day it ran. The
// check that matters for a disbursement is the one taken at disbursement time —
// and it has to fail closed, because a payment released on a failed check is a
// payment nobody screened.
//
//	go run ./examples/ex-29-pre-disbursement-recheck
package main

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks/go/examples/internal/support"
	"github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks/go/internal/mockapi"
	"github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks/go/pactman"
)

// How long a screening result is allowed to stand before a payment. The other
// SDKs use the same 120 days; it is a threshold, not a fact about the data.
const maxResultAgeDays = 120

func main() {
	ctx := context.Background()

	// A payment gate is latency-sensitive and the answer is needed now, so the
	// timeout is short and retries are few. Failing fast is the point: the
	// fallback is "do not pay yet", which is safe.
	example := support.WithFixtures(
		pactman.WithTimeout(5*time.Second),
		pactman.WithRetryPolicy(support.QuickRetries(1)),
	)

	defer example.Close()

	held := 0

	for _, ein := range []string{
		mockapi.PublicCharity,
		mockapi.Revoked,
		mockapi.StaleData,
		mockapi.Slow,
	} {
		support.Heading("Disbursement check for " + ein)

		// A tight per-request budget: this call sits in the path of a payment.
		result, err := example.Nonprofits().Check(
			ctx, ein, pactman.WithTimeout(700*time.Millisecond))

		if err != nil {
			// Fail closed. The screen did not happen, so the payment does not
			// either.
			var pactmanErr pactman.Error

			if errors.As(err, &pactmanErr) {
				support.Field("error type", fmt.Sprintf("%T", err))
				support.Field("category", pactmanErr.Category())
			} else {
				support.Field("error", err.Error())
			}

			support.Field("decision", "HOLD — the re-check did not complete")
			held++

			continue
		}

		nonprofit := result.Nonprofit

		if nonprofit == nil {
			support.Field("decision", "HOLD — no record returned")
			held++

			continue
		}

		findings := support.ScreeningFindings(nonprofit)
		age := support.OldestSourceAgeDays(nonprofit)

		support.Field("organization", nonprofit.OrganizationName)

		if age == nil {
			support.Field("oldest source", nil)
		} else {
			support.Field("oldest source", fmt.Sprintf("%d days", *age))
		}

		for _, finding := range findings {
			support.Bullet(finding)
		}

		var decision string

		switch {
		case len(findings) > 0:
			decision = "HOLD — the re-check surfaced findings"
		case age != nil && *age > maxResultAgeDays:
			decision = "HOLD — the underlying data is older than this gate allows"
		default:
			decision = "RELEASE under this gate's policy"
		}

		if decision != "RELEASE under this gate's policy" {
			held++
		}

		support.Field("decision", decision)
	}

	support.Heading("Gate summary")
	support.Field("held", held)

	if held != 3 {
		support.Fail("Three of the four should have been held, %d were.", held)
	}

	support.Note("Three of the four hold, for three different reasons: a finding, stale source\n" +
		"data, and a call that did not complete in time. Only the last one is about the\n" +
		"SDK, and it is the one worth being deliberate about — an error handler that\n" +
		"logs and continues would release a payment on the strength of a check that\n" +
		"never ran.\n\n" +
		"The stale-data hold is not a fault in the record. Nothing on it is adverse; it\n" +
		"is simply older than this gate is willing to rely on, and that is a threshold\n" +
		"you own.")
}
