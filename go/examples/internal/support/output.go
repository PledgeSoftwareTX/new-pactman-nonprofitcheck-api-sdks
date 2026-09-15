// Package support holds the small pieces the numbered examples share, so that
// each example file stays on its own subject.
//
// None of it is part of the SDK. The comparison, address and screening helpers
// in particular are customer policy questions the SDK deliberately refuses to
// answer: what counts as the same name, a usable address or a disqualifying
// finding differs between a donation platform, a donor-advised fund and a
// payout gate, and all of them are right for their own obligations.
package support

import (
	"encoding/json"
	"fmt"
	"os"
	"reflect"
	"strings"

	"github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks/go/pactman"
)

// absent is the type of Absent. It is its own type so that Render can tell it
// apart from any value an API could return.
type absent struct{}

func (absent) String() string { return "<not returned>" }

// Absent is what Render prints for a field the API did not return at all, as
// distinct from one it returned as null.
var Absent = absent{}

// Heading prints a section heading with a rule under it.
func Heading(text string) {
	fmt.Println()
	fmt.Println(text)
	fmt.Println(strings.Repeat("─", len([]rune(text))))
}

// Render renders a value for display, keeping "returned as null" and "not
// returned" apart.
//
// Collapsing the two into "" or "-" is how a missing value quietly becomes a
// match: a record with no OFAC field and a record screened clean print the same
// thing, and only one of them was screened.
func Render(value any) string {
	if value == nil {
		return "<null>"
	}

	if _, ok := value.(absent); ok {
		return "<not returned>"
	}

	if raw, ok := value.(json.RawMessage); ok {
		return renderRaw(raw)
	}

	reflected := reflect.ValueOf(value)

	switch reflected.Kind() {
	case reflect.Pointer:
		if reflected.IsNil() {
			return "<null>"
		}

		return Render(reflected.Elem().Interface())

	case reflect.Slice:
		// A list of strings is short enough to read, and in the bulk examples
		// the values are the point. Anything else is summarized.
		if list, ok := value.([]string); ok {
			if len(list) == 0 {
				return "<empty list>"
			}

			return "[" + strings.Join(list, ", ") + "]"
		}

		if reflected.Len() == 0 {
			return "<empty list>"
		}

		return fmt.Sprintf("%d entries", reflected.Len())

	case reflect.Map:
		return fmt.Sprintf("%d fields", reflected.Len())
	}

	return fmt.Sprint(value)
}

// renderRaw renders a field's value as the API sent it.
func renderRaw(raw json.RawMessage) string {
	trimmed := strings.TrimSpace(string(raw))

	if trimmed == "" || trimmed == "null" {
		return "<null>"
	}

	var decoded any
	if err := json.Unmarshal(raw, &decoded); err != nil {
		return trimmed
	}

	switch value := decoded.(type) {
	case string:
		return value
	case []any:
		if len(value) == 0 {
			return "<empty list>"
		}

		return fmt.Sprintf("%d entries", len(value))
	case map[string]any:
		return fmt.Sprintf("%d fields", len(value))
	default:
		return fmt.Sprint(value)
	}
}

// Field prints a labelled value.
func Field(label string, value any) {
	FieldWidth(label, value, 32)
}

// FieldWidth prints a labelled value with an explicit label column width.
func FieldWidth(label string, value any, width int) {
	padding := width - len([]rune(label))
	if padding < 0 {
		padding = 0
	}

	fmt.Println("  " + label + strings.Repeat(" ", padding) + " " + Render(value))
}

// Bullet prints a bulleted line.
func Bullet(text string) {
	fmt.Println("  • " + text)
}

// Note prints a closing note. Used for policy statements and caveats.
func Note(text string) {
	fmt.Println()
	fmt.Println(text)
}

// Present reads a field as Absent when the API did not return it, and as the
// value it sent otherwise — null included.
func Present(fields pactman.Object, name string) any {
	raw, ok := fields.Get(name)
	if !ok {
		return Absent
	}

	return raw
}

// Fail reports that an example did not demonstrate what it claims, and exits
// non-zero so that the smoke run notices.
func Fail(format string, args ...any) {
	fmt.Fprintf(os.Stderr, "FAILED: "+format+"\n", args...)
	os.Exit(1)
}

// Must exits when err is non-nil. Used for the calls an example needs to
// succeed for the rest of it to mean anything.
func Must(err error) {
	if err != nil {
		Fail("%v", err)
	}
}
