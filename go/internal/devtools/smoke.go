package main

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"time"

	"github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks/go/internal/contract"
	"github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks/go/pactman"
)

// baselineSource is the committed recording, relative to the module root. It
// is embedded into the contract package, so a rewrite takes effect on the next
// build.
const baselineSource = "internal/contract/response-baseline.json"

const reconcileHint = "\n      reconcile pactman/models.go and internal/contract/response-contract.json " +
	"with the API, once the change is understood and intended"

// liveResponses is one single and one bulk response from the deployment under
// test, reduced to their signatures.
type liveResponses struct {
	baseURL   string
	ein       string
	bulkEINs  []string
	single    contract.Signature
	bulk      contract.Signature
	singleErr error
	bulkErr   error
}

// check is one line of the report.
type check struct {
	status string // pass, fail or skip
	kind   string
	name   string
	detail string
	extra  string
}

// smokeLive holds a live deployment against what this package promises: the
// contract, and the committed recording of production.
//
// It spends real quota against a real key, so it is not part of CI.
func smokeLive(args []string) int {
	flags := flag.NewFlagSet("smoke-live", flag.ContinueOnError)
	baselinePath := flags.String("baseline", "", "compare against this recording instead of the committed one")
	ein, bulk := liveFlags(flags)

	if err := flags.Parse(args); err != nil {
		return 2
	}

	live, code := observe(*ein, *bulk)
	if code != 0 {
		return code
	}

	baseline, source, err := loadRecording(*baselinePath)
	if err != nil {
		fmt.Fprintln(os.Stderr, err)

		return 1
	}

	fmt.Printf("  recording : %s (recorded %s)\n", source, baseline.RecordedAt)

	results := againstContract(live)
	results = append(results, againstRecording(live, baseline)...)

	// Each endpoint's checks together: types, fields, then the recording.
	sort.SliceStable(results, func(i, j int) bool { return results[i].kind == "single" && results[j].kind != "single" })

	return report(results)
}

// recordBaseline rewrites the committed recording from a live deployment. It
// refuses when the responses break the contract: a recording is a statement of
// what production looks like, and a broken response is not that.
func recordBaseline(args []string) int {
	flags := flag.NewFlagSet("baseline-record", flag.ContinueOnError)
	ein, bulk := liveFlags(flags)

	if err := flags.Parse(args); err != nil {
		return 2
	}

	root, err := moduleRoot()
	if err != nil {
		fmt.Fprintln(os.Stderr, err)

		return 1
	}

	live, code := observe(*ein, *bulk)
	if code != 0 {
		return code
	}

	if failed := report(againstContract(live)); failed != 0 {
		fmt.Fprintln(os.Stderr, "\nThe live responses break the contract; fix that before recording them.")

		return failed
	}

	baseline := contract.Baseline{
		Note: "The shape production returned when this was recorded: path, JSON type and value format, " +
			"never a value. Committed, so every run of `go run ./internal/devtools smoke-live` is held " +
			"against the same recording — any path added or removed, and any token that changed, fails " +
			"there. Rewrite it with `go run ./internal/devtools baseline-record` only when production has " +
			"moved and the move is intended.",
		RecordedAt: time.Now().UTC().Format("2006-01-02T15:04:05.000Z"),
		BaseURL:    live.baseURL,
		SDKVersion: pactman.Version,
		Single:     &contract.Half{Signature: live.single},
		Bulk:       &contract.Half{Signature: live.bulk},
	}

	target := filepath.Join(root, baselineSource)

	if err := writeJSON(target, baseline); err != nil {
		fmt.Fprintln(os.Stderr, err)

		return 1
	}

	fmt.Printf("\nRecorded %d single and %d bulk paths to %s\n", len(live.single), len(live.bulk), baselineSource)

	return 0
}

// printContract prints the signature this package predicts for each endpoint.
func printContract() int {
	loaded, err := contract.Load()
	if err != nil {
		fmt.Fprintln(os.Stderr, err)

		return 1
	}

	for _, kind := range []string{"single", "bulk"} {
		expected := contract.ComposeExpected(loaded, kind)
		paths := make([]string, 0, len(expected))

		for path := range expected {
			paths = append(paths, path)
		}

		sort.Strings(paths)

		fmt.Printf("\n── %s ──\n", kind)

		for _, path := range paths {
			fmt.Printf("  %-56s%s\n", path, expected[path])
		}
	}

	return 0
}

func liveFlags(flags *flag.FlagSet) (ein, bulk *string) {
	ein = flags.String("ein", "411787097", "the EIN for the single check")
	bulk = flags.String("bulk", "", "comma-separated EINs for the bulk check (default: the single EIN and 996589560)")

	return ein, bulk
}

// observe makes one single and one bulk call and records their signatures.
func observe(ein, bulk string) (liveResponses, int) {
	apiKey := strings.TrimSpace(os.Getenv("PACTMAN_API_KEY"))
	if apiKey == "" {
		fmt.Fprintln(os.Stderr, "Set PACTMAN_API_KEY to run the live smoke check.")

		return liveResponses{}, 1
	}

	opts := []pactman.ClientOption{pactman.WithTimeout(20 * time.Second)}

	if baseURL := strings.TrimSpace(os.Getenv("PACTMAN_BASE_URL")); baseURL != "" {
		opts = append(opts, pactman.WithBaseURL(baseURL))
	}

	client, err := pactman.NewClient(apiKey, opts...)
	if err != nil {
		fmt.Fprintln(os.Stderr, err)

		return liveResponses{}, 1
	}

	bulkEINs := []string{ein, "996589560"}
	if bulk != "" {
		bulkEINs = strings.Split(bulk, ",")
	}

	live := liveResponses{baseURL: client.BaseURL(), ein: ein, bulkEINs: bulkEINs}

	fmt.Println("Pactman Nonprofit Check Plus — live smoke")
	fmt.Printf("  sdk       : %s\n", pactman.Version)
	fmt.Printf("  baseUrl   : %s\n", live.baseURL)
	fmt.Printf("  ein       : %s\n", ein)
	fmt.Printf("  bulk      : %s\n", strings.Join(bulkEINs, ", "))

	ctx := context.Background()

	if result, err := client.Nonprofits.Check(ctx, ein); err != nil {
		live.singleErr = err
	} else {
		live.single, live.singleErr = signatureOf(result.Raw)
	}

	if result, err := client.Nonprofits.CheckBulk(ctx, bulkEINs); err != nil {
		live.bulkErr = err
	} else {
		live.bulk, live.bulkErr = signatureOf(result.Raw)
	}

	return live, 0
}

func signatureOf(raw pactman.Envelope) (contract.Signature, error) {
	body, err := json.Marshal(raw)
	if err != nil {
		return nil, err
	}

	return contract.SignatureOf(body)
}

// againstContract asks whether the API still matches what this package
// promises: every value a form the contract permits, and every field the
// contract predicts either arriving or excused.
func againstContract(live liveResponses) []check {
	loaded, err := contract.Load()
	if err != nil {
		return []check{{status: "fail", kind: "contract", name: "load", detail: err.Error()}}
	}

	var results []check

	for _, kind := range []string{"single", "bulk"} {
		signature, err := live.half(kind)
		if err != nil {
			results = append(results,
				check{"fail", kind, "types", "the " + kind + " call failed: " + err.Error(), ""},
				check{"skip", kind, "fields", "no response to hold against the contract", ""})

			continue
		}

		paths := len(signature)
		expected := contract.ComposeExpected(loaded, kind)

		// Values the contract permits no form of: a boolean that turned into a
		// string, a timestamp that turned ISO.
		types := contract.ContractDiff(expected, signature)

		if types.Total == 0 {
			results = append(results, check{"pass", kind, "types",
				fmt.Sprintf("%d paths carry the predicted types and value formats", paths), ""})
		} else {
			results = append(results, check{"fail", kind, "types",
				fmt.Sprintf("the live %s response carries values this package does not predict — %s",
					kind, contract.SummarizeChanges(types.Changes)),
				contract.FormatChanges(types.Changes, "      ") + reconcileHint})
		}

		// Fields the API sent that the package does not predict, and fields it
		// predicts that the API did not send. Both directions fail.
		fields := contract.CoverageDiff(expected, signature, contract.RequiredPathsOf(loaded, kind))

		if fields.Total == 0 {
			results = append(results, check{"pass", kind, "fields",
				fmt.Sprintf("%d paths, all predicted · %d under a null or empty parent · %d optional and not sent",
					paths, fields.Unreachable, fields.OptionalAbsent), ""})
		} else {
			results = append(results, check{"fail", kind, "fields",
				fmt.Sprintf("the live %s response and this package disagree on which fields exist — %s",
					kind, contract.SummarizeChanges(fields.Changes)),
				contract.FormatChanges(fields.Changes, "      ") + reconcileHint})
		}
	}

	return results
}

// againstRecording asks whether the API has moved since the recording, with
// nullability and reachability excused: a recording is one organization on one
// afternoon, and those differ between two green runs.
func againstRecording(live liveResponses, baseline contract.Baseline) []check {
	var results []check

	for _, kind := range []string{"single", "bulk"} {
		signature, err := live.half(kind)
		recorded := baseline.Single

		if kind == "bulk" {
			recorded = baseline.Bulk
		}

		switch {
		case err != nil:
			results = append(results, check{"skip", kind, "recording", "no response to hold against the recording", ""})

			continue
		case recorded == nil || len(recorded.Signature) == 0:
			results = append(results, check{"skip", kind, "recording", "the recording has no " + kind + " signature", ""})

			continue
		}

		diff := contract.BaselineDiff(recorded.Signature, signature)

		if diff.Total == 0 {
			results = append(results, check{"pass", kind, "recording",
				fmt.Sprintf("%d paths, matching the recording · %d differ only in whether a value arrived · "+
					"%d under a null or empty parent", len(signature), diff.Nullable, diff.Unreachable), ""})
		} else {
			results = append(results, check{"fail", kind, "recording",
				fmt.Sprintf("the live %s response has moved since the recording — %s",
					kind, contract.SummarizeChanges(diff.Changes)),
				contract.FormatChanges(diff.Changes, "      ") +
					"\n      if production moved on purpose, rewrite the recording with baseline-record"})
		}
	}

	return results
}

func (l liveResponses) half(kind string) (contract.Signature, error) {
	if kind == "single" {
		return l.single, l.singleErr
	}

	return l.bulk, l.bulkErr
}

// loadRecording reads the committed recording, or the file at path.
func loadRecording(path string) (contract.Baseline, string, error) {
	if path == "" {
		baseline, err := contract.LoadBaseline()

		return baseline, "the committed recording", err
	}

	file, err := os.Open(path)
	if err != nil {
		return contract.Baseline{}, path, err
	}
	defer file.Close()

	body, err := io.ReadAll(file)
	if err != nil {
		return contract.Baseline{}, path, err
	}

	var baseline contract.Baseline
	if err := json.Unmarshal(body, &baseline); err != nil {
		return contract.Baseline{}, path, fmt.Errorf("%s is not a recording: %w", path, err)
	}

	return baseline, path, nil
}

// report prints the checks grouped by endpoint and returns how many failed.
func report(results []check) int {
	passed, failed, skipped := 0, 0, 0
	kind := ""

	for _, result := range results {
		if result.kind != kind {
			kind = result.kind
			fmt.Printf("\n%s  the live response against the contract and the recording\n", kind)
		}

		mark := map[string]string{"pass": "✓", "fail": "✗", "skip": "–"}[result.status]
		fmt.Printf("  %s %-13s %s\n", mark, result.name, result.detail)

		if result.extra != "" {
			fmt.Println(result.extra)
		}

		switch result.status {
		case "pass":
			passed++
		case "fail":
			failed++
		default:
			skipped++
		}
	}

	fmt.Printf("\n  %d checks: %d passed, %d failed, %d skipped\n", len(results), passed, failed, skipped)

	return failed
}

func writeJSON(path string, value any) error {
	var buffer bytes.Buffer

	encoder := json.NewEncoder(&buffer)
	encoder.SetEscapeHTML(false)
	encoder.SetIndent("", "  ")

	if err := encoder.Encode(value); err != nil {
		return err
	}

	if _, err := os.Stat(filepath.Dir(path)); errors.Is(err, os.ErrNotExist) {
		return fmt.Errorf("%s does not exist; run this from inside the Go module", filepath.Dir(path))
	}

	return os.WriteFile(path, buffer.Bytes(), 0o644)
}
