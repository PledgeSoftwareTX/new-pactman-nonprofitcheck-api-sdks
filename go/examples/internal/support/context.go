package support

import (
	"fmt"
	"os"
	"strings"
	"time"

	"github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks/go/internal/mockapi"
	"github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks/go/pactman"
)

// Context is the wiring every example shares: where requests go, and where the
// key comes from.
//
// Examples that need an ordinary lookup use Live and run against production, or
// against PACTMAN_BASE_URL when it is set. Examples that need a record or a
// response a live API will not produce on request — a revoked exemption, an
// OFAC match, an HTTP 429, an address that contradicts itself, a field newer
// than this SDK — use WithFixtures, which starts the bundled fixture API and
// shuts it down on the way out.
type Context struct {
	// Client is the client this example sends through.
	Client *pactman.Client

	fixtures *mockapi.Server
}

// Live returns a client pointed at production, or at PACTMAN_BASE_URL when it
// is set.
func Live(opts ...pactman.ClientOption) *Context {
	if override := BaseURLOverride(); override != "" {
		opts = append(opts, pactman.WithBaseURL(override))
	}

	client, err := pactman.NewClient(RequireAPIKey(), opts...)
	Must(err)

	return &Context{Client: client}
}

// WithFixtures returns a client pointed at the bundled fixture API.
//
// PACTMAN_BASE_URL still wins, so the same example can be aimed at a different
// mock or at a sandbox you have been given — and so the smoke runner can point
// every example at one shared server instead of thirty starting their own.
func WithFixtures(opts ...pactman.ClientOption) *Context {
	if override := BaseURLOverride(); override != "" {
		opts = append(opts, pactman.WithBaseURL(override))

		client, err := pactman.NewClient(RequireAPIKey(), opts...)
		Must(err)

		return &Context{Client: client}
	}

	const apiKey = "fixture-key"

	server, err := mockapi.Start(mockapi.Options{APIKey: apiKey})
	Must(err)

	fmt.Println("Using the bundled fixture API at " + server.URL + " — these scenarios need")
	fmt.Println("records and responses a live API will not produce on request.")

	opts = append(opts, pactman.WithBaseURL(server.URL))

	client, err := pactman.NewClient(apiKey, opts...)
	if err != nil {
		server.Close()
		Fail("%v", err)
	}

	return &Context{Client: client, fixtures: server}
}

// UsesFixtures reports whether this example's records come from the bundled
// fixture API rather than from a live deployment.
func (c *Context) UsesFixtures() bool { return c.fixtures != nil }

// Close releases the fixture API, when this context started one.
func (c *Context) Close() {
	if c.fixtures != nil {
		c.fixtures.Close()
	}
}

// Nonprofits is the resource every example calls through.
func (c *Context) Nonprofits() *pactman.NonprofitsResource { return c.Client.Nonprofits }

// RequireAPIKey returns the API key, or explains and exits.
//
// The key is never printed, embedded in a message, or written to a file.
func RequireAPIKey() string {
	apiKey := strings.TrimSpace(os.Getenv("PACTMAN_API_KEY"))

	if apiKey == "" {
		fmt.Fprintln(os.Stderr, "Set PACTMAN_API_KEY before running this example.")
		fmt.Fprintln(os.Stderr, "Load it from your secret manager or a .env file excluded from git.")
		os.Exit(1)
	}

	return apiKey
}

// BaseURLOverride returns an explicit host to use instead of production, or ""
// when none is configured.
func BaseURLOverride() string {
	return strings.TrimSpace(os.Getenv("PACTMAN_BASE_URL"))
}

// QuickRetries returns a retry policy with the delays shortened, so that an
// example demonstrating a retry does not spend the default backoff waiting.
//
// The defaults — 500ms growing by two, with full jitter — are what production
// should use.
func QuickRetries(maxRetries int) pactman.RetryPolicy {
	policy := pactman.DefaultRetryPolicy()
	policy.MaxRetries = maxRetries
	policy.InitialDelay = 50 * time.Millisecond
	policy.MaxDelay = 400 * time.Millisecond

	return policy
}
