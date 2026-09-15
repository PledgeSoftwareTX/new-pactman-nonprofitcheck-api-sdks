// Bulk: a bulk nonprofit check with local validation and result iteration.
//
//	PACTMAN_API_KEY=... go run ./examples/bulk
package main

import (
	"context"
	"errors"
	"fmt"
	"os"
	"strings"

	"github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks/go/pactman"
)

func main() {
	apiKey := os.Getenv("PACTMAN_API_KEY")
	if apiKey == "" {
		fmt.Fprintln(os.Stderr, "Set PACTMAN_API_KEY before running this example.")
		os.Exit(1)
	}

	var opts []pactman.ClientOption
	if baseURL := os.Getenv("PACTMAN_BASE_URL"); baseURL != "" {
		opts = append(opts, pactman.WithBaseURL(baseURL))
	}

	client, err := pactman.NewClient(apiKey, opts...)
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}

	eins := []string{"41-1787097", "996589560"}

	fmt.Printf("Checking %d EINs (server limit is %d per request).\n", len(eins), pactman.MaxBulkEINs)

	result, err := client.Nonprofits.CheckBulk(context.Background(), eins)

	var invalid *pactman.ValidationError
	if errors.As(err, &invalid) {
		// Nothing was sent — the whole batch is rejected before the request.
		fmt.Fprintln(os.Stderr, "Local validation failed, no request was sent:")

		for _, issue := range invalid.Issues {
			fmt.Fprintf(os.Stderr, "  index %d: %s\n", issue.Index, issue.Message)
		}

		os.Exit(1)
	}

	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}

	fmt.Printf("\nMatched %d organizations.\n", len(result.Organizations))

	for _, org := range result.Organizations {
		listed := "n/a"
		if pub78 := org.Pub78(); pub78 != nil && pub78.Verified != nil {
			listed = fmt.Sprint(*pub78.Verified)
		}

		fmt.Printf("  %s  %s  pub78_listed=%s\n", deref(org.EIN), deref(org.OrganizationName), listed)
	}

	// EINs with no record come back on a successful response, not as an error.
	if len(result.NotFoundEINs) > 0 {
		fmt.Printf("\nNo record for: %s\n", strings.Join(result.NotFoundEINs, ", "))
	}

	if result.CheckCount != nil {
		fmt.Printf("\nChecks used this billing cycle: %d\n", *result.CheckCount)
	}

	// Duplicates are sent as supplied, because each one consumes quota. Pass
	// pactman.WithDedupe() to collapse them first.
}

func deref(field *string) string {
	if field == nil {
		return "<no value>"
	}

	return *field
}
