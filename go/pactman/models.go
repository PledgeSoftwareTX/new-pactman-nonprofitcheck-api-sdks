package pactman

import (
	"encoding/json"
	"reflect"
	"time"
)

// Nonprofit is a nonprofit record as returned by the US nonprofit check
// endpoints.
//
// Source-specific findings are flat on the record, prefixed by source
// (Pub78*, BMF*, OFAC*, and the revocation fields for the IRS Automatic
// Revocation of Exemption list). Pub78, BMF, AROE and OFAC return grouped views.
//
// Every field is optional: the API omits fields it has no data for. A nil
// field means the API returned no value — either no field, or null. Fields
// tells those two apart, and holds any field a newer API version returns that
// this SDK does not declare.
//
// Declared here is what the production API returns. Some deployments serve
// additional source fields — the BMF address (bmf_city, bmf_state,
// bmf_street_address), bmf_source_pf_filing_req_cd, bmf_deductability_text,
// pub78_source_org_type_1..3, ofac_list_published_date and
// aroe_list_published_date. They are not declared because production does not
// return them; when it does they are readable through Fields, and this package
// will declare them in a release of its own.
//
// Nonprofit is a read view of a response. It marshals back to JSON as the
// fields the API sent, exactly; a Nonprofit built in code, with no Fields,
// marshals its non-nil declared fields.
type Nonprofit struct {
	// PactmanOrgURL is the organization's public Pactman profile URL.
	PactmanOrgURL                *string `json:"pactman_org_url"`
	OrganizationInfoLastModified *string `json:"organization_info_last_modified"`

	EIN                 *string `json:"ein"`
	OrganizationName    *string `json:"organization_name"`
	OrganizationNameAKA *string `json:"organization_name_aka"`
	AddressLine1        *string `json:"address_line1"`
	AddressLine2        *string `json:"address_line2"`
	City                *string `json:"city"`
	State               *string `json:"state"`
	StateName           *string `json:"state_name"`
	ZIP                 *string `json:"zip"`
	FilingReqCode       *string `json:"filing_req_code"`

	// IRS Publication 78.
	Pub78ChurchMessage    *string `json:"pub78_church_message"`
	Pub78OrganizationName *string `json:"pub78_organization_name"`
	Pub78EIN              *string `json:"pub78_ein"`
	Pub78Verified         *bool   `json:"pub78_verified"`
	Pub78City             *string `json:"pub78_city"`
	Pub78State            *string `json:"pub78_state"`
	Pub78Indicator        *string `json:"pub78_indicator"`
	// OrganizationTypes are the deductibility entries. An entry can itself be
	// nil, so read through it rather than into it.
	OrganizationTypes []*OrganizationType `json:"organization_types"`
	MostRecentPub78   *string             `json:"most_recent_pub78"`

	// IRS Business Master File.
	BMFChurchMessage          *string `json:"bmf_church_message"`
	BMFOrganizationName       *string `json:"bmf_organization_name"`
	BMFEIN                    *string `json:"bmf_ein"`
	BMFStatus                 *bool   `json:"bmf_status"`
	BMFSubsection             *string `json:"bmf_subsection"`
	MostRecentBMF             *string `json:"most_recent_bmf"`
	SubsectionDescription     *string `json:"subsection_description"`
	FoundationCode            *string `json:"foundation_code"`
	FoundationCodeDescription *string `json:"foundation_code_description"`
	FoundationTypeCode        *string `json:"foundation_type_code"`
	FoundationTypeDescription *string `json:"foundation_type_description"`
	Foundation509aStatus      *string `json:"foundation_509a_status"`
	RulingMonth               *string `json:"ruling_month"`
	RulingYear                *string `json:"ruling_year"`
	GroupExemption            *string `json:"group_exemption"`
	ExemptStatusCode          *string `json:"exempt_status_code"`

	// OFACStatus is the OFAC Specially Designated Nationals finding. The API
	// returns a sentence, not a flag — do not pattern-match it to derive a
	// boolean. Read it, or present it to a reviewer.
	OFACStatus *string `json:"ofac_status"`

	// IRS Automatic Revocation of Exemption.
	RevocationCode    *string `json:"revocation_code"`
	RevocationDate    *string `json:"revocation_date"`
	ReinstatementDate *string `json:"reinstatement_date"`

	// IRSBMFPub78Conflict is true when the IRS BMF and Publication 78 records disagree.
	IRSBMFPub78Conflict *bool   `json:"irs_bmf_pub78_conflict"`
	ReportDate          *string `json:"report_date"`

	// Fields is every field the API returned for this record, exactly as sent,
	// including null ones and ones this SDK does not declare.
	Fields Object `json:"-"`
}

// UnmarshalJSON reads a record, keeping every field in Fields.
func (n *Nonprofit) UnmarshalJSON(data []byte) error {
	return unmarshalModel(n, data, &n.Fields)
}

// MarshalJSON returns the record as the API sent it.
func (n Nonprofit) MarshalJSON() ([]byte, error) {
	return marshalModel(&n, n.Fields)
}

// OrganizationType is one deductibility entry from IRS Publication 78.
type OrganizationType struct {
	OrganizationType               *string `json:"organization_type"`
	DeductibilityLimitation        *string `json:"deductibility_limitation"`
	DeductibilityStatusDescription *string `json:"deductibility_status_description"`

	// Fields is every field the API returned for this entry, exactly as sent.
	Fields Object `json:"-"`
}

// UnmarshalJSON reads an entry, keeping every field in Fields.
func (o *OrganizationType) UnmarshalJSON(data []byte) error {
	return unmarshalModel(o, data, &o.Fields)
}

// MarshalJSON returns the entry as the API sent it.
func (o OrganizationType) MarshalJSON() ([]byte, error) {
	return marshalModel(&o, o.Fields)
}

// APIErrorDetail is one entry from the envelope's errors list.
type APIErrorDetail struct {
	// Resource is the API resource the error came from.
	Resource string `json:"resource"`
	// Reason is the human-readable explanation.
	Reason string `json:"reason"`
	// Code is the status for this specific failure, which may differ from the
	// HTTP status.
	Code *int `json:"code"`
	// EINs are the EINs this error applies to, for bulk requests. The API sends
	// them as a list or as one comma-separated string; both read as a list.
	EINs []string `json:"eins"`

	// Fields is every field the API returned for this entry, exactly as sent.
	Fields Object `json:"-"`
}

// UnmarshalJSON reads an entry, keeping every field in Fields.
func (d *APIErrorDetail) UnmarshalJSON(data []byte) error {
	return unmarshalModel(d, data, &d.Fields)
}

// MarshalJSON returns the entry as the API sent it.
func (d APIErrorDetail) MarshalJSON() ([]byte, error) {
	return marshalModel(&d, d.Fields)
}

// Envelope is the wrapper every nonprofit check response arrives in. The
// payload itself — data — is read into the result, and stays reachable
// through Fields.
type Envelope struct {
	Code    *int    `json:"code"`
	Message *string `json:"message"`
	// Errors are the item-level failures, normalized to a list. They appear on
	// successful responses too: a bulk request where some EINs were not found
	// is an HTTP 200 with entries here.
	Errors []APIErrorDetail `json:"errors"`
	// TimeTaken is the server-side processing time, in milliseconds.
	TimeTaken *float64 `json:"timeTaken"`
	// NonprofitCheckCount is the checks the account has consumed so far in the
	// current billing cycle, including this request. See Result.CheckCount.
	NonprofitCheckCount *int64 `json:"nonprofit_check_count"`

	// Fields is every field of the response body, exactly as sent.
	Fields Object `json:"-"`
}

// UnmarshalJSON reads a response body, keeping every field in Fields.
func (e *Envelope) UnmarshalJSON(data []byte) error {
	return unmarshalModel(e, data, &e.Fields)
}

// MarshalJSON returns the response body as it was received.
func (e Envelope) MarshalJSON() ([]byte, error) {
	return marshalModel(&e, e.Fields)
}

// Result holds the fields every result this SDK returns shares.
type Result struct {
	// CheckCount is nonprofit_check_count from the envelope: the checks
	// consumed so far in the current billing cycle, including this request,
	// resetting each cycle. It is not the size of this request; take the
	// difference between two responses for that. Nil when not reported.
	CheckCount *int64
	// TimeTaken is the server-side processing time, when reported.
	TimeTaken *time.Duration
	// Errors are item-level failures reported alongside a successful response.
	// Empty when the API reported none.
	Errors []APIErrorDetail
	// RequestID is the correlation identifier from the response headers, when
	// the server sent one.
	RequestID string
	// Status is the HTTP status of the response.
	Status int
	// Raw is the response body, unmodified, including fields not typed here.
	// json.Marshal(result.Raw) returns the body exactly as received.
	Raw Envelope
}

// SingleCheckResult is the result of NonprofitsResource.Check.
type SingleCheckResult struct {
	Result
	// Nonprofit is the organization, or nil when the API returned no record.
	Nonprofit *Nonprofit
}

// BulkCheckResult is the result of NonprofitsResource.CheckBulk.
type BulkCheckResult struct {
	Result
	// Organizations are the records the API matched, in the order it returned
	// them — which is not guaranteed to follow the order supplied. Index them
	// by EIN rather than pairing them positionally.
	Organizations []*Nonprofit
	// NotFoundEINs are the EINs the API reported no record for, collected from
	// Errors. A bulk request where some EINs miss is an HTTP 200, not an error.
	NotFoundEINs []string
}

func unmarshalModel(model any, data []byte, fields *Object) error {
	if isJSONNull(data) {
		return nil
	}

	parsed, err := parseObject(data)
	if err != nil {
		return err
	}

	reflect.ValueOf(model).Elem().Set(reflect.Zero(reflect.TypeOf(model).Elem()))
	*fields = parsed
	decodeDeclared(model, parsed)

	return nil
}

// marshalModel returns the wire fields when the model came from the wire, and
// otherwise the declared fields that are set.
func marshalModel(model any, fields Object) ([]byte, error) {
	if fields.src != nil {
		return fields.src, nil
	}

	value := reflect.ValueOf(model).Elem()
	typ := value.Type()
	out := map[string]any{}

	for i := 0; i < typ.NumField(); i++ {
		name := jsonName(typ.Field(i))
		field := value.Field(i)

		if name == "" || field.IsZero() {
			continue
		}

		out[name] = field.Interface()
	}

	return json.Marshal(out)
}
