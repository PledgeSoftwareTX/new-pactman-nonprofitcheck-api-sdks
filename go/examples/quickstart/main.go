// Quickstart: a minimal single nonprofit check.
//
//	PACTMAN_API_KEY=... go run ./examples/quickstart [EIN]
//
// The key is read from the environment. Never hard-code it, and never ship it
// anywhere an end user can read it — it is a private server-side credential.
package main

import (
	"context"
	"fmt"
	"os"
	"time"

	"github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks/go/pactman"
)

func main() {
	apiKey := os.Getenv("PACTMAN_API_KEY")
	if apiKey == "" {
		fmt.Fprintln(os.Stderr, "Set PACTMAN_API_KEY before running this example.")
		os.Exit(1)
	}

	opts := []pactman.ClientOption{pactman.WithTimeout(15 * time.Second)}

	// Production is the default. PACTMAN_BASE_URL is only for a local mock server.
	if baseURL := os.Getenv("PACTMAN_BASE_URL"); baseURL != "" {
		opts = append(opts, pactman.WithBaseURL(baseURL))
	}

	client, err := pactman.NewClient(apiKey, opts...)
	if err != nil {
		fail(err)
	}

	ein := "41-1787097"
	if len(os.Args) > 1 {
		ein = os.Args[1]
	}

	result, err := client.Nonprofits.Check(context.Background(), ein)
	if err != nil {
		fail(err)
	}

	if result.Nonprofit == nil {
		fmt.Printf("No record for EIN %s.\n", ein)

		return
	}

	nonprofit := result.Nonprofit

	fmt.Printf("Organization : %s\n", value(nonprofit.OrganizationName))
	fmt.Printf("EIN          : %s\n", value(nonprofit.EIN))
	fmt.Printf("Location     : %s, %s\n", value(nonprofit.City), value(nonprofit.State))
	fmt.Printf("Profile      : %s\n", value(nonprofit.PactmanOrgURL))

	if result.CheckCount != nil {
		fmt.Printf("Checks used  : %d this billing cycle\n", *result.CheckCount)
	}

	// Source-specific findings, read straight from the API response.
	fmt.Println("\nIRS Publication 78")

	if pub78 := nonprofit.Pub78(); pub78 == nil {
		fmt.Println("  not returned")
	} else {
		fmt.Printf("  listed: %s, as of %s\n", flag(pub78.Verified), value(pub78.MostRecent))
	}

	fmt.Println("\nIRS Business Master File")

	if bmf := nonprofit.BMF(); bmf == nil {
		fmt.Println("  not returned")
	} else {
		fmt.Printf("  status: %s, subsection: %s\n", flag(bmf.Status), value(bmf.SubsectionDescription))
	}

	fmt.Println("\nOFAC")

	if ofac := nonprofit.OFAC(); ofac == nil {
		fmt.Println("  not returned")
	} else {
		fmt.Printf("  %s\n", value(ofac.Status))
	}

	// A well-formed EIN and a clean set of findings are not an eligibility
	// decision. Apply your own grantmaking, compliance and risk policy.
}

// value prints an optional field. nil means the API returned no value.
func value(field *string) string {
	if field == nil {
		return "<no value>"
	}

	return *field
}

func flag(field *bool) string {
	if field == nil {
		return "<no value>"
	}

	return fmt.Sprint(*field)
}

func fail(err error) {
	fmt.Fprintln(os.Stderr, err)
	os.Exit(1)
}
