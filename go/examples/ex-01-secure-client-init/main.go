// EX-01 — Secure client initialization.
//
// Loads the API key from the environment, selects an environment, configures a
// finite timeout and builds one reusable client. Then it proves the key reaches
// no log, no error and no debug output.
//
//	PACTMAN_API_KEY=... go run ./examples/ex-01-secure-client-init
package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"log/slog"
	"time"

	"github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks/go/examples/internal/support"
	"github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks/go/pactman"
)

func main() {
	// 1. The key comes from the environment. It is never a literal in source,
	//    never committed, and never shipped inside a binary an end user can
	//    read — anyone who runs strings(1) over a binary holding this key owns
	//    your quota.
	apiKey := support.RequireAPIKey()

	opts := []pactman.ClientOption{
		// Production is the default; naming it makes the intent explicit at
		// review time.
		pactman.WithEnvironment(pactman.EnvironmentProduction),
		// 2. A finite timeout. The default is 30s and there is no way to
		//    disable it, but a caller-facing service usually wants less.
		pactman.WithTimeout(10 * time.Second),
	}

	// A mock, or a host Pactman gave you directly, replaces the environment.
	if override := support.BaseURLOverride(); override != "" {
		opts = append(opts, pactman.WithBaseURL(override))
	}

	// 3. One client, built once, reused for the life of the process.
	//    Constructing one per request throws away connection reuse and any
	//    throttle state.
	client, err := pactman.NewClient(apiKey, opts...)
	support.Must(err)

	support.Heading("Resolved configuration")
	support.Field("BaseURL()", client.BaseURL())
	support.Field("Environment()", client.Environment())
	support.Field("Timeout()", client.Timeout())
	support.Field("SDK default timeout", pactman.DefaultTimeout)

	// 4. An unusable option is rejected at construction, before any request.
	_, configErr := pactman.NewClient(apiKey, pactman.WithBaseURL("not-a-url"))

	if configErr == nil {
		support.Fail("A malformed base URL should have been rejected at construction.")
	}

	errorJSON, err := json.Marshal(configErr)
	support.Must(err)

	clientJSON, err := json.Marshal(client)
	support.Must(err)

	var logged bytes.Buffer
	slog.New(slog.NewTextHandler(&logged, nil)).Info("built the client", "pactman", client)

	// 5. Every diagnostic surface, checked against the real key. None of them
	//    contain it: the key is not a field of the client, and no error type
	//    copies it into a message or a serialized form.
	surfaces := []struct {
		name  string
		value string
	}{
		{"fmt %v", fmt.Sprintf("%v", client)},
		{"fmt %s", fmt.Sprintf("%s", client)},
		{"fmt %#v", fmt.Sprintf("%#v", client)},
		{"json.Marshal(client)", string(clientJSON)},
		{"slog", logged.String()},
		{"error.Error()", configErr.Error()},
		{"json.Marshal(error)", string(errorJSON)},
	}

	support.Heading("Credential redaction")

	leaked := false

	for _, surface := range surfaces {
		contains := bytes.Contains([]byte(surface.value), []byte(apiKey))
		leaked = leaked || contains

		status := "clean"
		if contains {
			status = "LEAKED THE KEY"
		}

		support.Field(surface.name, status)
	}

	support.Heading("The client as printed")
	fmt.Println("  " + fmt.Sprintf("%v", client))
	fmt.Println("  " + string(clientJSON))

	support.Note("The key is sent only as an Authorization header at request time. It is held\n" +
		"in an unexported type whose every formatting method prints a placeholder, so\n" +
		"the redaction above is a property of the type rather than a habit of this\n" +
		"example.\n\n" +
		"Rotate the key if it is ever printed, logged, or committed.")

	if leaked {
		support.Fail("The API key reached a diagnostic surface.")
	}
}
