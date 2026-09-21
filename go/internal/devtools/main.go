// Command devtools runs this SDK's development tasks. Run it from the module
// root (the go directory):
//
//	go run ./internal/devtools mock [port]                the fixture API, standalone
//	go run ./internal/devtools examples-smoke [filter...]  every example, against the fixture API
//	go run ./internal/devtools contract                    the signature this package predicts
//	go run ./internal/devtools smoke-live                  a live deployment against the contract and the recording
//	go run ./internal/devtools baseline-record             rewrite the committed recording from a live deployment
//
// examples-smoke is what CI uses to keep the documented examples honest. Set
// EXAMPLES_VERBOSE=1 to see each example's output. smoke-live and
// baseline-record spend real quota: set PACTMAN_API_KEY, and PACTMAN_BASE_URL
// to point them anywhere but production.
package main

import (
	"context"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"os/signal"
	"path/filepath"
	"regexp"
	"runtime"
	"sort"
	"strconv"
	"strings"
	"time"

	"github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks/go/internal/mockapi"
)

const usage = `Usage:
  go run ./internal/devtools mock [port]
  go run ./internal/devtools examples-smoke [filter...]
  go run ./internal/devtools contract
  go run ./internal/devtools smoke-live [-ein EIN] [-bulk EIN,EIN] [-baseline PATH]
  go run ./internal/devtools baseline-record [-ein EIN] [-bulk EIN,EIN]`

func main() {
	if len(os.Args) < 2 {
		fmt.Fprintln(os.Stderr, usage)
		os.Exit(2)
	}

	switch os.Args[1] {
	case "mock":
		os.Exit(runMock(os.Args[2:]))
	case "examples-smoke":
		os.Exit(examplesSmoke(os.Args[2:]))
	case "contract":
		os.Exit(printContract())
	case "smoke-live":
		os.Exit(min(smokeLive(os.Args[2:]), 1))
	case "baseline-record":
		os.Exit(min(recordBaseline(os.Args[2:]), 1))
	default:
		fmt.Fprintln(os.Stderr, usage)
		os.Exit(2)
	}
}

func runMock(args []string) int {
	port := 4010

	if len(args) > 0 {
		parsed, err := strconv.Atoi(args[0])
		if err != nil {
			fmt.Fprintf(os.Stderr, "%q is not a port\n", args[0])

			return 2
		}

		port = parsed
	}

	server, err := mockapi.Start(mockapi.Options{Port: port})
	if err != nil {
		fmt.Fprintln(os.Stderr, err)

		return 1
	}

	defer server.Close()

	fmt.Printf("Mock Pactman API listening on %s — Ctrl-C to stop\n", server.URL)

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt)
	defer stop()

	<-ctx.Done()

	return 0
}

const (
	smokeAPIKey       = "mock-key"
	perExampleTimeout = 60 * time.Second
)

var numbered = regexp.MustCompile(`^ex-\d{2}-`)

func examplesSmoke(filters []string) int {
	root, err := moduleRoot()
	if err != nil {
		fmt.Fprintln(os.Stderr, err)

		return 1
	}

	examples, err := discoverExamples(filepath.Join(root, "examples"), filters)
	if err != nil {
		fmt.Fprintln(os.Stderr, err)

		return 1
	}

	bin, err := os.MkdirTemp("", "pactman-examples-")
	if err != nil {
		fmt.Fprintln(os.Stderr, err)

		return 1
	}

	defer os.RemoveAll(bin)

	build := exec.Command("go", "build", "-o", bin+string(filepath.Separator), "./examples/...")
	build.Dir, build.Stdout, build.Stderr = root, os.Stdout, os.Stderr

	if err := build.Run(); err != nil {
		fmt.Fprintln(os.Stderr, "the examples do not build:", err)

		return 1
	}

	server, err := mockapi.Start(mockapi.Options{APIKey: smokeAPIKey})
	if err != nil {
		fmt.Fprintln(os.Stderr, err)

		return 1
	}

	defer server.Close()

	verbose := os.Getenv("EXAMPLES_VERBOSE") == "1"

	var failures []string

	fmt.Printf("Running %d examples against %s\n\n", len(examples), server.URL)

	for _, example := range examples {
		output, err := runExample(filepath.Join(bin, executable(example)), server.URL)

		// The one assertion this makes about content: no example may print the
		// credential it was given.
		if err == nil && strings.Contains(output, smokeAPIKey) {
			err = errors.New("printed the API key")
		}

		if err != nil {
			failures = append(failures, example)
			fmt.Fprintf(os.Stderr, "✗ %s: %v\n%s\n", example, err, indent(output))

			continue
		}

		fmt.Printf("✓ %s\n", example)

		if verbose {
			fmt.Println(indent(output))
		}
	}

	fmt.Printf("\n%d/%d examples passed.\n", len(examples)-len(failures), len(examples))

	if len(failures) > 0 {
		fmt.Fprintf(os.Stderr, "Failed: %s\n", strings.Join(failures, ", "))

		return 1
	}

	return 0
}

func runExample(path, baseURL string) (string, error) {
	ctx, cancel := context.WithTimeout(context.Background(), perExampleTimeout)
	defer cancel()

	cmd := exec.CommandContext(ctx, path)
	cmd.Env = append(os.Environ(), "PACTMAN_API_KEY="+smokeAPIKey, "PACTMAN_BASE_URL="+baseURL)

	output, err := cmd.CombinedOutput()
	if ctx.Err() != nil {
		return string(output), fmt.Errorf("did not finish within %s", perExampleTimeout)
	}

	return string(output), err
}

// discoverExamples lists every example directory: the numbered ones first, so
// failures read in order, then the rest.
func discoverExamples(dir string, filters []string) ([]string, error) {
	entries, err := os.ReadDir(dir)
	if err != nil {
		return nil, err
	}

	var first, rest []string

	for _, entry := range entries {
		if !entry.IsDir() {
			continue
		}

		if _, err := os.Stat(filepath.Join(dir, entry.Name(), "main.go")); err != nil {
			continue
		}

		if !matches(entry.Name(), filters) {
			continue
		}

		if numbered.MatchString(entry.Name()) {
			first = append(first, entry.Name())
		} else {
			rest = append(rest, entry.Name())
		}
	}

	sort.Strings(first)
	sort.Strings(rest)

	return append(first, rest...), nil
}

func matches(name string, filters []string) bool {
	if len(filters) == 0 {
		return true
	}

	for _, filter := range filters {
		if strings.Contains(name, filter) {
			return true
		}
	}

	return false
}

func executable(name string) string {
	if runtime.GOOS == "windows" {
		return name + ".exe"
	}

	return name
}

func indent(output string) string {
	lines := strings.Split(strings.TrimRight(output, "\n"), "\n")

	for i, line := range lines {
		lines[i] = "    " + line
	}

	return strings.Join(lines, "\n")
}

// moduleRoot walks up from the working directory to the directory holding go.mod.
func moduleRoot() (string, error) {
	dir, err := os.Getwd()
	if err != nil {
		return "", err
	}

	for {
		if _, err := os.Stat(filepath.Join(dir, "go.mod")); err == nil {
			return dir, nil
		}

		parent := filepath.Dir(dir)
		if parent == dir {
			return "", errors.New("run this from inside the Go module; no go.mod was found above the working directory")
		}

		dir = parent
	}
}
