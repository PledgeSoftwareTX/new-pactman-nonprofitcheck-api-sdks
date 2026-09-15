// EX-20 — The batch limit, and chunking a larger list yourself.
//
// The SDK will not split an oversized batch for you. Splitting turns one call a
// caller intended into several billable calls they did not, so it is a decision
// the caller makes.
//
//	go run ./examples/ex-20-bulk-batch-limits
package main

import (
	"context"
	"errors"

	"github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks/go/examples/internal/support"
	"github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks/go/internal/mockapi"
	"github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks/go/pactman"
)

func main() {
	ctx := context.Background()
	example := support.WithFixtures()

	defer example.Close()

	support.Heading("The limit is enforced locally")
	support.Field("pactman.MaxBulkEINs", pactman.MaxBulkEINs)

	support.Heading("An empty batch")

	_, err := example.Nonprofits().CheckBulk(ctx, nil)

	if !errors.Is(err, pactman.ErrValidation) {
		support.Fail("An empty batch should have been rejected, got %v.", err)
	}

	support.Field("sent", 0)
	support.Field("message", err.Error())

	support.Heading("An over-limit batch")

	tooMany := make([]string, pactman.MaxBulkEINs+1)
	for i := range tooMany {
		tooMany[i] = mockapi.PublicCharity
	}

	_, err = example.Nonprofits().CheckBulk(ctx, tooMany)

	if !errors.Is(err, pactman.ErrValidation) {
		support.Fail("An oversized batch should have been rejected, got %v.", err)
	}

	support.Field("EINs", len(tooMany))
	support.Field("sent", 0)
	support.Field("message", err.Error())

	support.Heading("Chunking a larger list")

	// A real workload would hold hundreds of EINs. Chunking is a few lines, and
	// doing it here means the caller can see how many billable requests they
	// are about to make.
	everything := []string{}

	for i := 0; i < 6; i++ {
		everything = append(everything,
			mockapi.PublicCharity, mockapi.PublicCharitySecond, mockapi.PrivateFoundation)
	}

	const batchSize = 5

	batches, matched := 0, 0

	for start := 0; start < len(everything); start += batchSize {
		end := start + batchSize
		if end > len(everything) {
			end = len(everything)
		}

		result, err := example.Nonprofits().CheckBulk(ctx, everything[start:end])
		support.Must(err)

		batches++
		matched += len(result.Organizations)
	}

	support.Field("EINs", len(everything))
	support.Field("batch size", batchSize)
	support.Field("requests made", batches)
	support.Field("organizations returned", matched)

	support.Note("The batch size above is 5 to keep the example short; the API's limit is 50 and\n" +
		"a real workload should use it. Note that duplicates within a chunk are still\n" +
		"sent — pass WithDedupe(), or clean the input, if the list came from somewhere\n" +
		"you do not control.")
}
