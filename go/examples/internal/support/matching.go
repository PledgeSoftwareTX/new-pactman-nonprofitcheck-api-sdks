package support

import (
	"regexp"
	"strings"
)

// Comparison is how two names compared. It is never a verdict about the
// applicant.
type Comparison string

// The three outcomes of a name comparison.
const (
	// Agree: the names are the same once formatting is normalized away.
	Agree Comparison = "AGREE"
	// Differ: both names are present and they are not the same.
	Differ Comparison = "DIFFER"
	// Uncomparable: one side is missing, so there is nothing to compare.
	Uncomparable Comparison = "UNCOMPARABLE"
)

// Legal suffixes carry no identifying information.
var legalSuffixes = map[string]bool{
	"INC": true, "INCORPORATED": true, "LLC": true, "LTD": true,
	"CO": true, "CORP": true, "CORPORATION": true,
}

// Abbreviations seen in IRS records versus what applicants type.
var abbreviations = map[string]string{
	"ASSN": "ASSOCIATION", "ASSOC": "ASSOCIATION", "CTR": "CENTER", "CENTRE": "CENTER",
	"FDN": "FOUNDATION", "FND": "FOUNDATION", "INTL": "INTERNATIONAL", "NATL": "NATIONAL",
	"ORG": "ORGANIZATION", "SOC": "SOCIETY", "ST": "SAINT", "UNIV": "UNIVERSITY",
	"DEPT": "DEPARTMENT", "MT": "MOUNT",
}

var nonAlphanumeric = regexp.MustCompile(`[^A-Z0-9]+`)

// NormalizeName reduces a name to the words that identify it.
//
// Case, punctuation, spacing, common abbreviations and legal suffixes all come
// out, because none of them distinguish one organization from another. The
// result is nil when there is nothing left to compare.
func NormalizeName(name *string) *string {
	if name == nil {
		return nil
	}

	cleaned := strings.TrimSpace(nonAlphanumeric.ReplaceAllString(
		strings.ReplaceAll(strings.ToUpper(*name), "&", " AND "), " "))

	if cleaned == "" {
		return nil
	}

	words := make([]string, 0, 8)

	for _, word := range strings.Fields(cleaned) {
		expanded := word
		if replacement, ok := abbreviations[word]; ok {
			expanded = replacement
		}

		if legalSuffixes[expanded] {
			continue
		}

		words = append(words, expanded)
	}

	if len(words) == 0 {
		return nil
	}

	normalized := strings.Join(words, " ")

	return &normalized
}

// CompareNames compares two names. A missing side is Uncomparable, never
// agreement: scoring an absent value as a match is how a blank record passes a
// name check.
func CompareNames(left, right *string) Comparison {
	first := NormalizeName(left)
	second := NormalizeName(right)

	if first == nil || second == nil {
		return Uncomparable
	}

	if *first == *second {
		return Agree
	}

	return Differ
}

// WordOverlap is the share of words the two names have in common, as evidence
// for a review queue rather than a threshold to automate on. It is nil when
// either side is missing.
func WordOverlap(left, right *string) *float64 {
	first := NormalizeName(left)
	second := NormalizeName(right)

	if first == nil || second == nil {
		return nil
	}

	inFirst := wordSet(*first)
	inSecond := wordSet(*second)

	shared, union := 0, len(inFirst)

	for word := range inSecond {
		if inFirst[word] {
			shared++
		} else {
			union++
		}
	}

	if union == 0 {
		return nil
	}

	overlap := float64(shared) / float64(union)

	return &overlap
}

func wordSet(text string) map[string]bool {
	set := make(map[string]bool)

	for _, word := range strings.Fields(text) {
		set[word] = true
	}

	return set
}

// Text dereferences an optional string for use in a message, rendering a
// missing value the same way Render does.
func Text(value *string) string {
	if value == nil {
		return "<null>"
	}

	return *value
}
