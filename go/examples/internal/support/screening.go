package support

import (
	"strings"

	"github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks/go/pactman"
)

// OFACState is what the OFAC field said. Unavailable is never a pass.
type OFACState string

// The states the OFAC field can be read as.
const (
	// OFACUnavailable: the API returned no OFAC data at all for this organization.
	OFACUnavailable OFACState = "UNAVAILABLE"
	// OFACNull: the API returned the field, with no value in it.
	OFACNull OFACState = "NULL"
	// OFACMatch: the wording names a possible SDN match.
	OFACMatch OFACState = "MATCH"
	// OFACNoMatch: the wording says the organization was not on the list.
	OFACNoMatch OFACState = "NO_MATCH"
	// OFACUnrecognized: the API said something this reader does not recognize.
	OFACUnrecognized OFACState = "UNRECOGNIZED"
)

// ReadOFAC classifies the OFAC field.
//
// Reading prose is a last resort, and it is done here — in an example, in the
// caller's own code — rather than in the SDK, precisely because the wording can
// change. OFACUnrecognized is the outcome when it does, and a workflow should
// route that to a person rather than treat it as a pass.
func ReadOFAC(nonprofit *pactman.Nonprofit) OFACState {
	ofac := nonprofit.OFAC()

	if ofac == nil {
		return OFACUnavailable
	}

	if ofac.Status == nil {
		return OFACNull
	}

	text := strings.ToUpper(*ofac.Status)

	if strings.Contains(text, "UID:") {
		return OFACMatch
	}

	if strings.Contains(text, "NOT INCLUDED") {
		return OFACNoMatch
	}

	return OFACUnrecognized
}

// OldestSourceAgeDays returns the age in days of the oldest source date on the
// record, or nil when no source date could be read.
func OldestSourceAgeDays(nonprofit *pactman.Nonprofit) *int64 {
	var oldest *int64

	for _, value := range []*string{
		nonprofit.MostRecentBMF,
		nonprofit.MostRecentPub78,
		nonprofit.OrganizationInfoLastModified,
	} {
		age := AgeInDays(value)

		if age != nil && (oldest == nil || *age > *oldest) {
			oldest = age
		}
	}

	return oldest
}

// RevokedAndNotReinstated reports whether the record shows an automatic
// revocation that was never reinstated. It is true only when a revocation date
// is present and no reinstatement date is.
func RevokedAndNotReinstated(nonprofit *pactman.Nonprofit) bool {
	aroe := nonprofit.AROE()

	return aroe != nil && aroe.RevocationDate != nil && aroe.ReinstatementDate == nil
}

// ScreeningFindings gathers everything on the record a reviewer would want to
// see, as plain sentences.
//
// Deliberately not scored, ranked or reduced to a flag. Two workflows can read
// the same list and route it differently, which is the point: a donation
// platform, a donor-advised fund and a payout gate reach different conclusions
// from identical data, and all three are right for their own obligations.
func ScreeningFindings(nonprofit *pactman.Nonprofit) []string {
	findings := []string{}

	pub78 := nonprofit.Pub78()
	bmf := nonprofit.BMF()
	aroe := nonprofit.AROE()

	switch {
	case pub78 == nil:
		findings = append(findings, "Publication 78: no data returned")
	case pub78.Verified == nil || !*pub78.Verified:
		findings = append(findings,
			"Publication 78: not listed (pub78_verified is "+Render(pub78.Verified)+")")
	}

	switch {
	case bmf == nil:
		findings = append(findings, "Business Master File: no data returned")
	case bmf.Status == nil || !*bmf.Status:
		findings = append(findings,
			"Business Master File: not exempt (bmf_status is "+Render(bmf.Status)+")")
	}

	if nonprofit.IRSBMFPub78Conflict != nil && *nonprofit.IRSBMFPub78Conflict {
		findings = append(findings,
			"The API flagged a disagreement between the BMF and Publication 78")
	}

	if aroe != nil && aroe.RevocationDate != nil {
		if aroe.ReinstatementDate == nil {
			findings = append(findings, "Exemption automatically revoked on "+
				*aroe.RevocationDate+", with no reinstatement date")
		} else {
			findings = append(findings, "Exemption revoked on "+*aroe.RevocationDate+
				" and reinstated on "+*aroe.ReinstatementDate)
		}
	}

	switch ReadOFAC(nonprofit) {
	case OFACMatch:
		findings = append(findings, "OFAC: the API reported a possible SDN match")
	case OFACUnavailable:
		findings = append(findings, "OFAC: no data returned — absence is not a no-match")
	case OFACNull:
		findings = append(findings, "OFAC: the field was returned with no value")
	case OFACUnrecognized:
		findings = append(findings,
			"OFAC: wording this reader does not recognize — read it yourself")
	case OFACNoMatch:
	}

	return findings
}
