// Error handling: branching on error category — local validation,
// authentication, rate limits — in one place, with no string parsing.
//
//	PACTMAN_API_KEY=... go run ./examples/error-handling
package main

import (
	"context"
	"errors"
	"fmt"
	"os"
	"strings"
	"time"

	"github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks/go/pactman"
)

func main() {
	apiKey := os.Getenv("PACTMAN_API_KEY")
	if apiKey == "" {
		fmt.Fprintln(os.Stderr, "Set PACTMAN_API_KEY before running this example.")
		os.Exit(1)
	}

	ctx := context.Background()

	client, err := pactman.NewClient(apiKey, withBaseURL(pactman.WithTimeout(10*time.Second), pactman.WithMaxRetries(2))...)
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}

	// 1. A malformed EIN never leaves the process.
	_, err = client.Nonprofits.Check(ctx, "41178709")
	fmt.Println("malformed EIN ->", explain(err))

	// 2. An empty batch is rejected locally too.
	_, err = client.Nonprofits.CheckBulk(ctx, nil)
	fmt.Println("empty batch   ->", explain(err))

	// 3. A bad key produces an authentication error on first use.
	badClient, err := pactman.NewClient("obviously-not-a-real-key", withBaseURL(pactman.WithoutRetries())...)
	if err == nil {
		_, err = badClient.Nonprofits.Check(ctx, "411787097")
	}

	fmt.Println("bad key       ->", explain(err))

	// 4. A real call, handled the same way.
	result, err := client.Nonprofits.Check(ctx, "41-1787097")
	if err != nil {
		fmt.Println("valid check   ->", explain(err))
	} else if result.Nonprofit == nil || result.Nonprofit.OrganizationName == nil {
		fmt.Println("valid check   -> no record")
	} else {
		fmt.Println("valid check   ->", *result.Nonprofit.OrganizationName)
	}
}

// explain turns any SDK failure into an action. It branches on category and
// type, never on message text.
func explain(err error) string {
	var (
		invalid  *pactman.ValidationError
		apiErr   *pactman.APIError
		timedOut *pactman.TimeoutError
	)

	switch {
	case err == nil:
		return "unexpectedly succeeded"

	case errors.As(err, &invalid):
		reasons := make([]string, 0, len(invalid.Issues))
		for _, issue := range invalid.Issues {
			reasons = append(reasons, issue.Message)
		}

		if len(reasons) == 0 {
			reasons = append(reasons, invalid.Error())
		}

		return "Local validation — fix the input. " + strings.Join(reasons, " ")

	case errors.Is(err, pactman.ErrAuthentication):
		return "Authentication — the API key was rejected. Check PACTMAN_API_KEY."

	case errors.Is(err, pactman.ErrRateLimit):
		errors.As(err, &apiErr)

		if apiErr.RetryAfter != nil {
			return fmt.Sprintf("Rate limited — retry after %s.", *apiErr.RetryAfter)
		}

		return "Rate limited — retry after an unspecified delay."

	case errors.As(err, &timedOut):
		return fmt.Sprintf("Timed out after %s — raise the timeout or retry later.", timedOut.Timeout)

	case errors.Is(err, pactman.ErrNetwork):
		return "Network failure — the request never reached the API, or the caller cancelled it."

	case errors.As(err, &apiErr):
		requestID := apiErr.RequestID
		if requestID == "" {
			requestID = "unknown"
		}

		return fmt.Sprintf("API error %d (request %s): %s", apiErr.Status, requestID, apiErr.APIMessage)
	}

	return "Unexpected: " + err.Error()
}

// withBaseURL points the client at PACTMAN_BASE_URL when it is set.
// Production is the default; the variable is only for a local mock server.
func withBaseURL(opts ...pactman.ClientOption) []pactman.ClientOption {
	if baseURL := os.Getenv("PACTMAN_BASE_URL"); baseURL != "" {
		opts = append(opts, pactman.WithBaseURL(baseURL))
	}

	return opts
}
