// Package contract holds the shape of a response against two standards: what
// this package promises (response-contract.json) and what production returned
// when it was last recorded (response-baseline.json).
//
// A recorded copy of a live response is worthless as a drift detector: every
// run returns a fresh report_date, a different timeTaken and a usage counter
// that only goes up. What is stable is the shape — which fields exist, what
// type each carries, and what form its values take. A Signature captures that:
// a flat map of path to type token.
//
//	"code":                                              "number"
//	"data.ein":                                          "digits:9"
//	"data.most_recent_bmf":                              "date"
//	"data.organization_types[].deductibility_limitation": "text"
//	"errors":                                            "null"
//
// Tokens
//
//	object, array, boolean, number, null   the JSON type, structural
//	date            M/D/YYYY h:mm:ss AM — the format every API timestamp uses
//	date:iso        an ISO-8601 timestamp, which this API does not send
//	digits:9        a string of digits, grouped by length: "01085-2643" is digits:5-4
//	url             an http(s) URL
//	ofac-sentence   the SDN sentence ofac_status carries, in either wording
//	empty           an empty or whitespace-only string
//	text            any other string
//
// A path that carries more than one token across one response records them
// sorted and joined by "|", as in date|null. No value from a response is ever
// recorded, so a baseline is safe to commit and a diff is safe to print.
//
// This is a port of the Node SDK's scripts/contract.mjs, which is the source of
// truth for these rules; response-contract.json is a byte-identical copy of the
// Node SDK's, held so by a test.
package contract

import (
	"bytes"
	_ "embed"
	"encoding/json"
	"errors"
	"fmt"
	"regexp"
	"sort"
	"strings"
)

//go:embed response-contract.json
var contractJSON []byte

//go:embed response-baseline.json
var baselineJSON []byte

// Contract is what this package predicts each response looks like.
type Contract struct {
	Note             string              `json:"note"`
	Required         map[string][]string `json:"required"`
	Envelope         map[string]string   `json:"envelope"`
	ErrorDetail      map[string]string   `json:"errorDetail"`
	Nonprofit        map[string]string   `json:"nonprofit"`
	OrganizationType map[string]string   `json:"organizationType"`
}

// Load reads the embedded contract.
func Load() (Contract, error) {
	var contract Contract
	err := json.Unmarshal(contractJSON, &contract)

	return contract, err
}

// ContractJSON returns the embedded contract file, byte for byte.
func ContractJSON() []byte { return append([]byte(nil), contractJSON...) }

// Signature is the shape of one response: path to type token.
type Signature map[string]string

// Half is one endpoint's recorded shape.
type Half struct {
	Signature Signature `json:"signature"`
}

// Baseline is the shape production returned when it was recorded.
type Baseline struct {
	Note       string `json:"note"`
	RecordedAt string `json:"recordedAt"`
	BaseURL    string `json:"baseUrl"`
	SDKVersion string `json:"sdkVersion"`
	Single     *Half  `json:"single"`
	Bulk       *Half  `json:"bulk"`
}

// LoadBaseline reads the embedded baseline.
func LoadBaseline() (Baseline, error) {
	var baseline Baseline
	err := json.Unmarshal(baselineJSON, &baseline)

	return baseline, err
}

var (
	apiDate      = regexp.MustCompile(`(?i)^\d{1,2}/\d{1,2}/\d{4},? \d{1,2}:\d{2}:\d{2} ?(?:AM|PM)$`)
	isoDate      = regexp.MustCompile(`^\d{4}-\d{2}-\d{2}(?:[T ]\d{2}:\d{2}|$)`)
	digitGroups  = regexp.MustCompile(`^\d+(?:-\d+)*$`)
	urlLike      = regexp.MustCompile(`(?i)^https?://`)
	ofacSentence = regexp.MustCompile(`(?i)Specially Designated Nationals ?\(SDN\) list`)

	// Newer runtimes format times with a narrow no-break space; the API sends
	// a plain one. Normalized so the same timestamp is not two tokens.
	spaces = strings.NewReplacer(" ", " ", " ", " ")
)

// FormatOf classifies a string by the form of its value, never by the value.
//
// The OFAC clause is matched rather than either whole sentence, so a genuine
// change of wording falls back to text while a subject moving from "was NOT
// included" to "may be included" stays the same shape.
func FormatOf(value string) string {
	text := spaces.Replace(value)

	switch {
	case strings.TrimSpace(text) == "":
		return "empty"
	case apiDate.MatchString(text):
		return "date"
	case isoDate.MatchString(text):
		return "date:iso"
	case digitGroups.MatchString(text):
		groups := strings.Split(text, "-")
		lengths := make([]string, len(groups))

		for i, group := range groups {
			lengths[i] = fmt.Sprint(len(group))
		}

		return "digits:" + strings.Join(lengths, "-")
	case urlLike.MatchString(text):
		return "url"
	case ofacSentence.MatchString(text):
		return "ofac-sentence"
	}

	return "text"
}

// SignatureOf builds the signature of a JSON response body.
//
// Every element of an array contributes to one path, so a batch of ten
// organizations describes one record shape rather than ten.
func SignatureOf(body []byte) (Signature, error) {
	if !json.Valid(body) {
		return nil, errors.New("contract: the body is not JSON")
	}

	tokens := map[string]map[string]bool{}

	if err := collect(bytes.TrimSpace(body), "", tokens); err != nil {
		return nil, err
	}

	signature := Signature{}

	for path, set := range tokens {
		signature[path] = joinSorted(set)
	}

	return signature, nil
}

func collect(raw []byte, path string, tokens map[string]map[string]bool) error {
	if path != "" {
		if tokens[path] == nil {
			tokens[path] = map[string]bool{}
		}

		tokens[path][tokenOf(raw)] = true
	}

	switch raw[0] {
	case '[':
		var items []json.RawMessage
		if err := json.Unmarshal(raw, &items); err != nil {
			return err
		}

		for _, item := range items {
			if err := collect(bytes.TrimSpace(item), path+"[]", tokens); err != nil {
				return err
			}
		}
	case '{':
		var fields map[string]json.RawMessage
		if err := json.Unmarshal(raw, &fields); err != nil {
			return err
		}

		for key, child := range fields {
			childPath := key
			if path != "" {
				childPath = path + "." + key
			}

			if err := collect(bytes.TrimSpace(child), childPath, tokens); err != nil {
				return err
			}
		}
	}

	return nil
}

func tokenOf(raw []byte) string {
	switch raw[0] {
	case 'n':
		return "null"
	case 't', 'f':
		return "boolean"
	case '[':
		return "array"
	case '{':
		return "object"
	case '"':
		var text string
		_ = json.Unmarshal(raw, &text)

		return FormatOf(text)
	}

	return "number"
}

func joinSorted(set map[string]bool) string {
	tokens := make([]string, 0, len(set))
	for token := range set {
		tokens = append(tokens, token)
	}

	sort.Strings(tokens)

	return strings.Join(tokens, "|")
}

// Change is one difference between two signatures.
type Change struct {
	Kind  string `json:"kind"` // removed, changed or added
	Path  string `json:"path"`
	Token string `json:"token,omitempty"` // removed and added
	From  string `json:"from,omitempty"`  // changed
	To    string `json:"to,omitempty"`    // changed
}

// Diff is the outcome of comparing two signatures. Nullable, Unreachable and
// OptionalAbsent count differences passed over, so a green run still says how
// much it did not hold against.
type Diff struct {
	Changes        []Change
	Total          int
	Nullable       int
	Unreachable    int
	OptionalAbsent int
}

func sortedPaths(signature Signature) []string {
	paths := make([]string, 0, len(signature))
	for path := range signature {
		paths = append(paths, path)
	}

	sort.Strings(paths)

	return paths
}

// changeOrder puts removals first: a field that disappeared breaks callers
// that read it.
var changeOrder = map[string]int{"removed": 0, "changed": 1, "added": 2}

func finish(changes []Change) Diff {
	sort.SliceStable(changes, func(i, j int) bool {
		if changeOrder[changes[i].Kind] != changeOrder[changes[j].Kind] {
			return changeOrder[changes[i].Kind] < changeOrder[changes[j].Kind]
		}

		return changes[i].Path < changes[j].Path
	})

	if changes == nil {
		changes = []Change{}
	}

	return Diff{Changes: changes, Total: len(changes)}
}

// SchemaDiff reports fields the API stopped sending and fields it started
// sending. Additions count: a field the API added is forward compatible for a
// caller, but it is still the API changing.
func SchemaDiff(baseline, current Signature) Diff {
	var changes []Change

	for _, path := range sortedPaths(baseline) {
		if _, ok := current[path]; !ok {
			changes = append(changes, Change{Kind: "removed", Path: path, Token: baseline[path]})
		}
	}

	for _, path := range sortedPaths(current) {
		if _, ok := baseline[path]; !ok {
			changes = append(changes, Change{Kind: "added", Path: path, Token: current[path]})
		}
	}

	return finish(changes)
}

// TypeDiff reports fields whose type or value format changed, across the
// paths both signatures have.
func TypeDiff(baseline, current Signature) Diff {
	var changes []Change

	for _, path := range sortedPaths(baseline) {
		if now, ok := current[path]; ok && now != baseline[path] {
			changes = append(changes, Change{Kind: "changed", Path: path, From: baseline[path], To: now})
		}
	}

	return finish(changes)
}

// BaselineDiff holds a live response against a recording, leaving out the
// differences a recording has no standing to judge.
//
// A baseline is one organization's response on one afternoon. Nullability — a
// field that was text when recorded and is null now — and reachability — the
// paths under a parent that arrived null on either side — are counted, not
// reported. A move between two real forms (digits:9 to text) is drift and
// stays reported.
func BaselineDiff(before, current Signature) Diff {
	var changes []Change

	nullable, unreachable := 0, 0

	for _, path := range sortedPaths(before) {
		token := before[path]

		if now, ok := current[path]; ok {
			switch {
			case now == token:
			case nullabilityOnly(token, now):
				nullable++
			default:
				changes = append(changes, Change{Kind: "changed", Path: path, From: token, To: now})
			}

			continue
		}

		if unreachableIn(path, current) {
			unreachable++
			continue
		}

		changes = append(changes, Change{Kind: "removed", Path: path, Token: token})
	}

	for _, path := range sortedPaths(current) {
		if _, ok := before[path]; ok {
			continue
		}

		if unreachableIn(path, before) {
			unreachable++
			continue
		}

		changes = append(changes, Change{Kind: "added", Path: path, Token: current[path]})
	}

	diff := finish(changes)
	diff.Nullable, diff.Unreachable = nullable, unreachable

	return diff
}

// nullabilityOnly reports whether two tokens differ only over whether a value
// arrived: drop null from both and compare what is left. A side that recorded
// no form makes no claim about the form.
func nullabilityOnly(before, after string) bool {
	left, right := withoutNull(before), withoutNull(after)

	if len(left) == 0 || len(right) == 0 {
		return true
	}

	if len(left) != len(right) {
		return false
	}

	for i := range left {
		if left[i] != right[i] {
			return false
		}
	}

	return true
}

func withoutNull(token string) []string {
	var forms []string

	for _, one := range strings.Split(token, "|") {
		if one != "null" {
			forms = append(forms, one)
		}
	}

	return forms
}

// SummarizeChanges is "2 removed, 1 added" — the counts that are not zero.
func SummarizeChanges(changes []Change) string {
	counts := map[string]int{}
	for _, change := range changes {
		counts[change.Kind]++
	}

	var parts []string

	for _, kind := range []string{"removed", "changed", "added"} {
		if counts[kind] > 0 {
			parts = append(parts, fmt.Sprintf("%d %s", counts[kind], kind))
		}
	}

	if len(parts) == 0 {
		return "no differences"
	}

	return strings.Join(parts, ", ")
}

var marks = map[string]string{"removed": "-", "changed": "~", "added": "+"}

// FormatChanges renders one line per change, every change, nothing elided.
func FormatChanges(changes []Change, indent string) string {
	lines := make([]string, len(changes))

	for i, change := range changes {
		if change.Kind == "changed" {
			lines[i] = fmt.Sprintf("%s~ %s: %s → %s", indent, change.Path, change.From, change.To)
		} else {
			lines[i] = fmt.Sprintf("%s%s %s (%s)", indent, marks[change.Kind], change.Path, change.Token)
		}
	}

	return strings.Join(lines, "\n")
}

// stringTokens are the forms a declared "string" stands for when the contract
// claims no format.
var stringTokens = map[string]bool{"text": true, "date": true, "date:iso": true, "url": true, "ofac-sentence": true, "empty": true}

// IsStringToken reports whether a token is a form of JSON string.
func IsStringToken(token string) bool {
	return stringTokens[token] || strings.HasPrefix(token, "digits:")
}

// Permits reports whether an observed token is one the contract allows.
// "string" is a wildcard over every string token; where the contract names a
// form instead — digits:9, date — a value that stops matching it fails even
// though it is still a string.
func Permits(allowed, token string) bool {
	for _, one := range strings.Split(allowed, "|") {
		if one == token || (one == "string" && IsStringToken(token)) {
			return true
		}
	}

	return false
}

// ComposeExpected is the flat expected signature for one endpoint, "single" or
// "bulk". The record is described once and used for both, so the two cannot
// drift apart in the contract the way they can on the wire.
func ComposeExpected(contract Contract, kind string) Signature {
	single := kind == "single"
	prefix := "data[]."

	expected := Signature{}
	for field, token := range contract.Envelope {
		expected[field] = token
	}

	expected["data"] = "array|null"
	if single {
		prefix = "data."
		expected["data"] = "null|object"
	} else {
		expected["data[]"] = "object"
	}

	expected["errors[]"] = "object"
	expected["errors[].eins[]"] = "string"

	for field, token := range contract.ErrorDetail {
		expected["errors[]."+field] = token
	}

	for field, token := range contract.Nonprofit {
		expected[prefix+field] = token
	}

	// Nullable elements, not just a nullable list: the API sends a null where
	// Publication 78 has a deductibility row it cannot resolve.
	expected[prefix+"organization_types[]"] = "null|object"

	for field, token := range contract.OrganizationType {
		expected[prefix+"organization_types[]."+field] = token
	}

	return expected
}

// ContractDiff reports paths where the live response carries a value the
// contract permits no form of. Paths the contract has never heard of are
// CoverageDiff's to report.
func ContractDiff(expected, observed Signature) Diff {
	var changes []Change

	for _, path := range sortedPaths(observed) {
		allowed, ok := expected[path]
		if !ok {
			continue
		}

		var offending []string

		for _, one := range strings.Split(observed[path], "|") {
			if !Permits(allowed, one) {
				offending = append(offending, one)
			}
		}

		if len(offending) > 0 {
			changes = append(changes, Change{Kind: "changed", Path: path, From: allowed, To: strings.Join(offending, "|")})
		}
	}

	return finish(changes)
}

// CoverageDiff reports fields the API sent that the contract does not predict,
// and fields it predicts that the API did not send.
//
// A path that had nowhere to arrive — under a parent that came back null or
// as an empty list — is counted as unreachable. A vanished container is
// reported once, at its shallowest path. With required given, a predicted path
// outside it is optional, and its absence keeps the promise; with nil, every
// predicted path is treated as required.
func CoverageDiff(expected, observed Signature, required map[string]bool) Diff {
	var changes []Change

	for _, path := range sortedPaths(observed) {
		if _, ok := expected[path]; !ok {
			changes = append(changes, Change{Kind: "added", Path: path, Token: observed[path]})
		}
	}

	missing := map[string]bool{}

	var absent []string

	for _, path := range sortedPaths(expected) {
		if _, ok := observed[path]; !ok {
			missing[path] = true
			absent = append(absent, path)
		}
	}

	unreachable, optionalAbsent := 0, 0

	for _, path := range absent {
		if unreachableIn(path, observed) {
			unreachable++
			continue
		}

		if anyAncestor(path, func(ancestor string) bool { return missing[ancestor] }) {
			continue
		}

		if required != nil && !required[path] {
			optionalAbsent++
			continue
		}

		changes = append(changes, Change{Kind: "removed", Path: path, Token: expected[path]})
	}

	diff := finish(changes)
	diff.Unreachable, diff.OptionalAbsent = unreachable, optionalAbsent

	return diff
}

// RequiredPathsOf is the paths a response must carry: the structural ones
// every envelope has, and whatever the contract's required block names.
func RequiredPathsOf(contract Contract, kind string) map[string]bool {
	single := kind == "single"
	prefix := "data[]."

	if single {
		prefix = "data."
	}

	paths := map[string]bool{"data": true, "errors[]": true, "errors[].eins[]": true, prefix + "organization_types[]": true}

	if !single {
		paths["data[]"] = true
	}

	for _, field := range contract.Required["envelope"] {
		paths[field] = true
	}

	for _, field := range contract.Required["errorDetail"] {
		paths["errors[]."+field] = true
	}

	for _, field := range contract.Required["nonprofit"] {
		paths[prefix+field] = true
	}

	for _, field := range contract.Required["organizationType"] {
		paths[prefix+"organization_types[]."+field] = true
	}

	return paths
}

// anyAncestor walks a path's enclosing paths, innermost first:
// data.organization_types[].organization_type → data.organization_types[],
// data.organization_types, data.
func anyAncestor(path string, test func(string) bool) bool {
	rest := path

	for {
		if strings.HasSuffix(rest, "[]") {
			rest = strings.TrimSuffix(rest, "[]")
		} else {
			dot := strings.LastIndex(rest, ".")
			if dot == -1 {
				return false
			}

			rest = rest[:dot]
		}

		if test(rest) {
			return true
		}
	}
}

// unreachableIn reports whether a container above the path arrived in a form
// with no room for it: a null has no members and an empty list no elements.
func unreachableIn(path string, observed Signature) bool {
	return anyAncestor(path, func(ancestor string) bool {
		token, ok := observed[ancestor]
		if !ok {
			return false
		}

		tokens := strings.Split(token, "|")
		allNull := true
		hasArray := false

		for _, one := range tokens {
			allNull = allNull && one == "null"
			hasArray = hasArray || one == "array"
		}

		_, hasElements := observed[ancestor+"[]"]

		return allNull || (hasArray && !hasElements)
	})
}
