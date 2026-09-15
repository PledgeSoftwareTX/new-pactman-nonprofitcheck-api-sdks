package pactman

import "reflect"

// The grouped views below are projections, not derivations: every field is
// copied 1:1 from one the API returned. Nothing here computes an "approved",
// "eligible" or "safe" verdict, and nothing infers a value from another field.
//
// Each accessor returns nil only when the API returned none of that source's
// fields at all. That keeps "the source was not returned" distinguishable from
// an explicit negative such as pub78_verified: false or a null field. Every
// accessor is safe to call on a nil *Nonprofit.

// Pub78Source holds the IRS Publication 78 findings.
type Pub78Source struct {
	Verified          *bool
	OrganizationName  *string
	EIN               *string
	City              *string
	State             *string
	Indicator         *string
	ChurchMessage     *string
	OrganizationTypes []*OrganizationType
	MostRecent        *string
}

// BMFSource holds the IRS Business Master File findings.
type BMFSource struct {
	Status                    *bool
	OrganizationName          *string
	EIN                       *string
	ChurchMessage             *string
	Subsection                *string
	SubsectionDescription     *string
	FoundationCode            *string
	FoundationCodeDescription *string
	FoundationTypeCode        *string
	FoundationTypeDescription *string
	Foundation509aStatus      *string
	RulingMonth               *string
	RulingYear                *string
	GroupExemption            *string
	ExemptStatusCode          *string
	FilingReqCode             *string
	MostRecent                *string
}

// AROESource holds the IRS Automatic Revocation of Exemption findings.
type AROESource struct {
	RevocationCode    *string
	RevocationDate    *string
	ReinstatementDate *string
}

// OFACSource holds the OFAC Specially Designated Nationals findings.
type OFACSource struct {
	// Status is the finding as the API phrases it. It is prose, not a flag;
	// the API does not return a boolean match indicator, and this SDK does not
	// invent one by matching on the wording.
	Status *string
}

// Wire fields behind each source, in the order the API reference lists them.
var (
	pub78Wire = []string{
		"pub78_verified", "pub78_organization_name", "pub78_ein", "pub78_city", "pub78_state",
		"pub78_indicator", "pub78_church_message", "organization_types", "most_recent_pub78",
	}
	bmfWire = []string{
		"bmf_status", "bmf_organization_name", "bmf_ein", "bmf_church_message", "bmf_subsection",
		"subsection_description", "foundation_code", "foundation_code_description",
		"foundation_type_code", "foundation_type_description", "foundation_509a_status",
		"ruling_month", "ruling_year", "group_exemption", "exempt_status_code", "filing_req_code",
		"most_recent_bmf",
	}
	aroeWire = []string{"revocation_code", "revocation_date", "reinstatement_date"}
	ofacWire = []string{"ofac_status"}
)

// Pub78 returns the Publication 78 findings, or nil if the API returned none.
func (n *Nonprofit) Pub78() *Pub78Source {
	if !n.returnedAny(pub78Wire) {
		return nil
	}

	return &Pub78Source{
		Verified:          n.Pub78Verified,
		OrganizationName:  n.Pub78OrganizationName,
		EIN:               n.Pub78EIN,
		City:              n.Pub78City,
		State:             n.Pub78State,
		Indicator:         n.Pub78Indicator,
		ChurchMessage:     n.Pub78ChurchMessage,
		OrganizationTypes: n.OrganizationTypes,
		MostRecent:        n.MostRecentPub78,
	}
}

// BMF returns the Business Master File findings, or nil if the API returned none.
func (n *Nonprofit) BMF() *BMFSource {
	if !n.returnedAny(bmfWire) {
		return nil
	}

	return &BMFSource{
		Status:                    n.BMFStatus,
		OrganizationName:          n.BMFOrganizationName,
		EIN:                       n.BMFEIN,
		ChurchMessage:             n.BMFChurchMessage,
		Subsection:                n.BMFSubsection,
		SubsectionDescription:     n.SubsectionDescription,
		FoundationCode:            n.FoundationCode,
		FoundationCodeDescription: n.FoundationCodeDescription,
		FoundationTypeCode:        n.FoundationTypeCode,
		FoundationTypeDescription: n.FoundationTypeDescription,
		Foundation509aStatus:      n.Foundation509aStatus,
		RulingMonth:               n.RulingMonth,
		RulingYear:                n.RulingYear,
		GroupExemption:            n.GroupExemption,
		ExemptStatusCode:          n.ExemptStatusCode,
		FilingReqCode:             n.FilingReqCode,
		MostRecent:                n.MostRecentBMF,
	}
}

// AROE returns the Automatic Revocation of Exemption findings, or nil if the
// API returned none.
func (n *Nonprofit) AROE() *AROESource {
	if !n.returnedAny(aroeWire) {
		return nil
	}

	return &AROESource{
		RevocationCode:    n.RevocationCode,
		RevocationDate:    n.RevocationDate,
		ReinstatementDate: n.ReinstatementDate,
	}
}

// OFAC returns the OFAC findings, or nil if the API returned none.
func (n *Nonprofit) OFAC() *OFACSource {
	if !n.returnedAny(ofacWire) {
		return nil
	}

	return &OFACSource{Status: n.OFACStatus}
}

// nonprofitFieldIndex maps a wire name to its field on Nonprofit.
var nonprofitFieldIndex = func() map[string]int {
	typ := reflect.TypeOf(Nonprofit{})
	index := make(map[string]int, typ.NumField())

	for i := 0; i < typ.NumField(); i++ {
		if name := jsonName(typ.Field(i)); name != "" {
			index[name] = i
		}
	}

	return index
}()

// returnedAny reports whether any of the wire fields is on the record: sent by
// the API (null included), or set on a record built in code.
func (n *Nonprofit) returnedAny(wire []string) bool {
	if n == nil {
		return false
	}

	value := reflect.ValueOf(n).Elem()

	for _, name := range wire {
		if n.Fields.Has(name) {
			return true
		}

		if i, ok := nonprofitFieldIndex[name]; ok && !value.Field(i).IsNil() {
			return true
		}
	}

	return false
}
