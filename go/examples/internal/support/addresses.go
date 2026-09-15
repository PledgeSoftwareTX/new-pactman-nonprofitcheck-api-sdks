package support

import (
	"strings"

	"github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks/go/pactman"
)

// Values that occupy a field without saying anything.
var placeholders = map[string]bool{
	"N/A": true, "NA": true, "NONE": true, "NULL": true, "UNKNOWN": true, "-": true, ".": true,
}

// The two-letter codes, paired with the names the API spells out.
var stateNames = map[string]string{
	"AL": "ALABAMA", "AK": "ALASKA", "AZ": "ARIZONA", "AR": "ARKANSAS",
	"CA": "CALIFORNIA", "CO": "COLORADO", "CT": "CONNECTICUT", "DE": "DELAWARE",
	"DC": "DISTRICT OF COLUMBIA", "FL": "FLORIDA", "GA": "GEORGIA", "HI": "HAWAII",
	"ID": "IDAHO", "IL": "ILLINOIS", "IN": "INDIANA", "IA": "IOWA",
	"KS": "KANSAS", "KY": "KENTUCKY", "LA": "LOUISIANA", "ME": "MAINE",
	"MD": "MARYLAND", "MA": "MASSACHUSETTS", "MI": "MICHIGAN", "MN": "MINNESOTA",
	"MS": "MISSISSIPPI", "MO": "MISSOURI", "MT": "MONTANA", "NE": "NEBRASKA",
	"NV": "NEVADA", "NH": "NEW HAMPSHIRE", "NJ": "NEW JERSEY", "NM": "NEW MEXICO",
	"NY": "NEW YORK", "NC": "NORTH CAROLINA", "ND": "NORTH DAKOTA", "OH": "OHIO",
	"OK": "OKLAHOMA", "OR": "OREGON", "PA": "PENNSYLVANIA", "RI": "RHODE ISLAND",
	"SC": "SOUTH CAROLINA", "SD": "SOUTH DAKOTA", "TN": "TENNESSEE", "TX": "TEXAS",
	"UT": "UTAH", "VT": "VERMONT", "VA": "VIRGINIA", "WA": "WASHINGTON",
	"WV": "WEST VIRGINIA", "WI": "WISCONSIN", "WY": "WYOMING", "PR": "PUERTO RICO",
}

// IsPlaceholder reports whether a value occupies a field without filling it.
func IsPlaceholder(value *string) bool {
	return value != nil && placeholders[strings.ToUpper(strings.TrimSpace(*value))]
}

// StateName returns the spelled-out name for a two-letter code, or "" when the
// code is not one this table knows.
func StateName(code *string) string {
	if code == nil {
		return ""
	}

	return stateNames[strings.ToUpper(strings.TrimSpace(*code))]
}

// AddressFindings reports everything questionable about the address on a
// record.
//
// These are observations, not a verdict: an address that produces findings may
// still be perfectly mailable, and the caller decides. The point of the checks
// is that a field being non-null is not the same as a field being usable — a
// placeholder, a contradiction between components, or a state code that
// disagrees with the spelled-out state all survive a null check, and none of
// them survive reading.
func AddressFindings(nonprofit *pactman.Nonprofit) []string {
	findings := []string{}

	if nonprofit.AddressLine1 == nil {
		findings = append(findings, "address_line1 is null — there is no street address to use")
	}

	if IsPlaceholder(nonprofit.AddressLine1) {
		findings = append(findings, "address_line1 is a placeholder: \""+*nonprofit.AddressLine1+"\"")
	}

	if IsPlaceholder(nonprofit.AddressLine2) {
		findings = append(findings, "address_line2 is a placeholder: \""+*nonprofit.AddressLine2+"\"")
	}

	if nonprofit.ZIP == nil {
		findings = append(findings, "zip is null — a mailing address without one is incomplete")
	}

	expected := StateName(nonprofit.State)

	if expected != "" && nonprofit.StateName != nil &&
		!strings.EqualFold(expected, strings.TrimSpace(*nonprofit.StateName)) {
		findings = append(findings, "state \""+*nonprofit.State+"\" is "+expected+
			", but state_name says \""+*nonprofit.StateName+"\"")
	}

	if nonprofit.State != nil && expected == "" {
		findings = append(findings,
			"state \""+*nonprofit.State+"\" is not a code this table knows")
	}

	if nonprofit.Pub78State != nil && nonprofit.State != nil &&
		!strings.EqualFold(strings.TrimSpace(*nonprofit.Pub78State), strings.TrimSpace(*nonprofit.State)) {
		findings = append(findings, "the BMF address says "+*nonprofit.State+
			" and Publication 78 says "+*nonprofit.Pub78State)
	}

	if nonprofit.Pub78City != nil && nonprofit.City != nil &&
		!strings.EqualFold(strings.TrimSpace(*nonprofit.Pub78City), strings.TrimSpace(*nonprofit.City)) {
		findings = append(findings, "the BMF address says "+*nonprofit.City+
			" and Publication 78 says "+*nonprofit.Pub78City)
	}

	return findings
}
