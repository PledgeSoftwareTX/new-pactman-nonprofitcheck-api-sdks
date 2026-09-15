package support

import (
	"strings"
	"time"
)

// The API formats timestamps for display, not for machines: M/DD/YYYY h:mm:ss AM.
//
// Parsing them means assuming a locale and a time zone, which is why the SDK
// hands them back as strings and leaves the assumption to code like this, where
// it is visible and can be argued with. The variants below are accepted because
// a display format is not a contract.
var apiDateLayouts = []string{
	"1/02/2006 3:04:05 PM",
	"1/2/2006 3:04:05 PM",
	"01/02/2006 3:04:05 PM",
	"1/02/2006 15:04:05",
	"2006-01-02",
}

// ParseAPIDate reads a timestamp the API returned. The second result is false
// when the value is not in a form this reader recognizes.
func ParseAPIDate(value string) (time.Time, bool) {
	trimmed := strings.TrimSpace(value)
	if trimmed == "" {
		return time.Time{}, false
	}

	for _, layout := range apiDateLayouts {
		if parsed, err := time.ParseInLocation(layout, trimmed, time.Local); err == nil {
			return parsed, true
		}
	}

	return time.Time{}, false
}

// AgeInDays returns how many days ago a timestamp was, or nil when the API
// returned no value or one this reader cannot parse.
//
// An unparseable date returns nil rather than zero: "today" is a much worse
// answer than "I do not know".
func AgeInDays(value *string) *int64 {
	if value == nil {
		return nil
	}

	parsed, ok := ParseAPIDate(*value)
	if !ok {
		return nil
	}

	days := int64(time.Since(parsed) / (24 * time.Hour))

	return &days
}
