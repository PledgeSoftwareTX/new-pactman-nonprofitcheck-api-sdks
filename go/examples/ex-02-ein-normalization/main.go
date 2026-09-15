// EX-02 — EIN normalization and validation.
//
// Every accepted spelling of an EIN, every rejected one, and what the SDK says
// about each. No request is sent: this all happens locally, which is the point —
// a malformed EIN should never cost a billable call.
//
//	go run ./examples/ex-02-ein-normalization
package main

import (
	"errors"
	"fmt"

	"github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks/go/examples/internal/support"
	"github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks/go/pactman"
)

func main() {
	support.Heading("Accepted spellings")

	for _, input := range []string{"411787097", "41-1787097", "  41-1787097  "} {
		normalized, err := pactman.NormalizeEIN(input)
		support.Must(err)
		support.Field("\""+input+"\"", normalized)
	}

	support.Heading("Rejected values")

	for _, input := range []string{
		"41178709", "4117870977", "41-178709", "41 1787097", "abcdefghi", "",
	} {
		_, err := pactman.NormalizeEIN(input)

		if err == nil {
			support.Fail("%q should not have been accepted.", input)
		}

		support.FieldWidth("\""+input+"\"", err.Error(), 16)
	}

	// A batch reports every failure at once, by index, so that a caller fixes
	// one upload rather than discovering the next bad row on the next attempt.
	support.Heading("A batch reports every failure at once")

	_, err := pactman.NormalizeEINs([]string{"411787097", "nope", "996589560", "1234"})

	if err == nil {
		support.Fail("The batch should have been rejected.")
	}

	fmt.Println("  " + err.Error())
	fmt.Println()

	var validation *pactman.ValidationError

	if !errors.As(err, &validation) {
		support.Fail("A malformed batch should return a *pactman.ValidationError.")
	}

	for _, issue := range validation.Issues {
		support.Bullet(fmt.Sprintf("index %d: %q — %s", issue.Index, issue.Value, issue.Message))
	}

	support.Heading("Branching on the error")
	support.Field("errors.Is(err, pactman.ErrValidation)", errors.Is(err, pactman.ErrValidation))
	support.Field("category", validation.Category())
	support.Field("origin", validation.Origin())

	support.Heading("What validation does not tell you")
	support.Field("IsValidEIN(\"00-0000000\")", pactman.IsValidEIN("00-0000000"))

	support.Note("Formatting validation confirms only that a value is shaped like an EIN.\n" +
		"It says nothing about tax-exempt status, identity, eligibility, or good\n" +
		"standing. No IRS prefix rules are applied.")
}
