// Package pactman is the official Go client for the Pactman Nonprofit Check
// Plus API: look up US nonprofits by EIN and read the IRS and OFAC findings
// behind the result.
//
// Server-side only — the API key is a private credential.
//
//	client, err := pactman.NewClient(os.Getenv("PACTMAN_API_KEY"))
//	if err != nil {
//		return err
//	}
//
//	result, err := client.Nonprofits.Check(ctx, "41-1787097")
//	if err != nil {
//		return err
//	}
//
//	if result.Nonprofit != nil {
//		fmt.Println(*result.Nonprofit.OrganizationName, *result.CheckCount)
//	}
//
// # Errors
//
// Every error is an Error with a stable ErrorCategory and ErrorOrigin. Branch
// with errors.Is on the Err* sentinels, or errors.As on the concrete types —
// never on message text:
//
//	var apiErr *pactman.APIError
//	switch {
//	case errors.Is(err, pactman.ErrValidation):  // bad input; nothing was sent
//	case errors.Is(err, pactman.ErrRateLimit):   // apiErr.RetryAfter, when sent
//	case errors.As(err, &apiErr):                // any other HTTP failure
//	}
//
// # What this package does not tell you
//
// It exposes what the API returns and nothing more: no composite approved,
// eligible or safe verdict, and no boolean summarizing a source the API does
// not itself express as a boolean. A successful check is data, not a decision.
package pactman
