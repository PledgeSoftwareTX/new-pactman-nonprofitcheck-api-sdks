package pactman

import (
	"fmt"
	"regexp"
	"strconv"
	"strings"
)

// EINLength is the number of digits in an EIN.
const EINLength = 9

// Accepted input shapes: nine digits, optionally with the conventional hyphen
// after the two-digit prefix. Surrounding whitespace is ignored.
var einPattern = regexp.MustCompile(`^\d{2}-?\d{7}$`)

// NormalizeEIN normalizes an EIN to the nine-digit form the API expects.
//
// "41-1787097" and "411787097" both normalize to "411787097".
//
// This is formatting validation only. Passing it says nothing about whether an
// organization is tax-exempt, in good standing, or eligible for anything — only
// that the value is shaped like an EIN. No IRS prefix rules are applied.
//
// A malformed value returns a *ValidationError.
func NormalizeEIN(input string) (string, error) {
	if issue, bad := einIssue(input, -1); bad {
		return "", &ValidationError{msg: issue.Message, Issues: []ValidationIssue{issue}}
	}

	return strings.Replace(strings.TrimSpace(input), "-", "", 1), nil
}

// NormalizeEINs normalizes a list of EINs, reporting every failure at once.
//
// Order is retained and duplicates are preserved; see WithDedupe for
// CheckBulk's optional deduplication. A malformed item returns a
// *ValidationError whose Issues identify each failing item by index and value.
func NormalizeEINs(inputs []string) ([]string, error) {
	var issues []ValidationIssue

	normalized := make([]string, 0, len(inputs))

	for index, input := range inputs {
		if issue, bad := einIssue(input, index); bad {
			issues = append(issues, issue)
			continue
		}

		normalized = append(normalized, strings.Replace(strings.TrimSpace(input), "-", "", 1))
	}

	if len(issues) > 0 {
		positions := make([]string, len(issues))

		for i, issue := range issues {
			positions[i] = strconv.Itoa(issue.Index)
		}

		return nil, &ValidationError{
			msg: fmt.Sprintf("%d of %d EINs are invalid (at index %s); no request was sent",
				len(issues), len(inputs), strings.Join(positions, ", ")),
			Issues: issues,
		}
	}

	return normalized, nil
}

// IsValidEIN reports whether input is shaped like an EIN.
func IsValidEIN(input string) bool {
	_, bad := einIssue(input, -1)

	return !bad
}

func einIssue(input string, index int) (ValidationIssue, bool) {
	at := ""
	if index >= 0 {
		at = fmt.Sprintf(" at index %d", index)
	}

	trimmed := strings.TrimSpace(input)

	if trimmed == "" {
		return ValidationIssue{Message: "EIN" + at + " is empty", Index: index, Value: input}, true
	}

	if !einPattern.MatchString(trimmed) {
		return ValidationIssue{
			Message: fmt.Sprintf("EIN%s must be %d digits, optionally hyphenated as XX-XXXXXXX; received %q",
				at, EINLength, trimmed),
			Index: index,
			Value: input,
		}, true
	}

	return ValidationIssue{}, false
}
